package Complete::Path;

our $DATE = '2014-12-25'; # DATE
our $VERSION = '0.03'; # VERSION

use 5.010001;
use strict;
use warnings;

use Complete;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       complete_path
               );

our %SPEC;

$SPEC{complete_path} = {
    v => 1.1,
    summary => 'Complete path',
    description => <<'_',

Complete path, for anything path-like. Meant to be used as backend for other
functions like `Complete::Util::complete_file` or
`Complete::Module::complete_module`. Provides features like case-insensitive
matching, expanding intermediate paths, and case mapping.

Algorithm is to split path into path elements, listing (using the supplied
`list_func`) and perform filtering (using the supplied `filter_func`) at every
level.

_
    args => {
        word => {
            schema  => [str=>{default=>''}],
            pos     => 0,
        },
        list_func => {
            summary => 'Function to list the content of intermediate "dirs"',
            schema => 'code*',
            req => 1,
            description => <<'_',

Code will be called with arguments: ($path, $cur_path_elem, $is_intermediate).

Code should return an arrayref containing list of elements.

_
        },
        is_dir_func => {
            summary => 'Function to check whether a path is a "dir"',
            schema  => 'code*',
            req     => 1,
        },
        starting_path => {
            schema => 'str*',
            req => 1,
            default => '',
        },
        filter_func => {
            schema  => 'code*',
        },

        path_sep => {
            schema  => 'str*',
            default => '/',
        },
        ci => {
            summary => 'Case-insensitive matching',
            schema  => 'bool',
        },
        map_case => {
            summary => 'Treat _ (underscore) and - (dash) as the same',
            schema  => 'bool',
            description => <<'_',

This is another convenience option like `ci`, where you can type `-` (without
pressing Shift, at least in US keyboard) and can still complete `_` (underscore,
which is typed by pressing Shift, at least in US keyboard).

This option mimics similar option in bash/readline: `completion-map-case`.

_
        },
        exp_im_path => {
            summary => 'Expand intermediate paths',
            schema  => 'bool',
            description => <<'_',

This option mimics feature in zsh where when you type something like `cd
/h/u/b/myscript` and get `cd /home/ujang/bin/myscript` as a completion answer.

_
        },
        #result_prefix => {
        #    summary => 'Prefix each result with this string',
        #    schema  => 'str*',
        #},
    },
    result_naked => 1,
    result => {
        schema => 'array',
    },
};
sub complete_path {
    my %args   = @_;
    my $word   = $args{word} // "";
    my $path_sep = $args{path_sep} // '/';
    my $list_func   = $args{list_func};
    my $is_dir_func = $args{is_dir_func};
    my $filter_func = $args{filter_func};
    my $ci          = $args{ci} // $Complete::OPT_CI;
    my $map_case    = $args{map_case} // $Complete::OPT_MAP_CASE;
    my $exp_im_path = $args{exp_im_path} // $Complete::OPT_EXP_IM_PATH;
    my $result_prefix = $args{result_prefix};
    my $starting_path = $args{starting_path} // '';

    # split word by into path elements, as we want to dig level by level (needed
    # when doing case-insensitive search on a case-sensitive tree).
    my @intermediate_dirs;
    {
        @intermediate_dirs = split qr/\Q$path_sep/, $word;
        @intermediate_dirs = ('') if !@intermediate_dirs;
        push @intermediate_dirs, '' if $word =~ m!\Q$path_sep\E\z!;
    }

    # extract leaf path, because this one is treated differently
    my $leaf = pop @intermediate_dirs;
    @intermediate_dirs = ('') if !@intermediate_dirs;

    say "D:starting_path=<$starting_path>";
    say "D:intermediate_dirs=[",join(", ", map{"<$_>"} @intermediate_dirs),"]";
    say "D:leaf=<$leaf>";

    # candidate for intermediate paths. when doing case-insensitive search,
    # there maybe multiple candidate paths for each dir, for example if
    # word='../foo/s' and there is '../foo/Surya', '../Foo/sri', '../FOO/SUPER'
    # then candidate paths would be ['../foo', '../Foo', '../FOO'] and the
    # filename should be searched inside all those dirs. everytime we drill down
    # to deeper subdirectories, we adjust this list by removing
    # no-longer-eligible candidates.
    my @candidate_paths;

    for my $i (0..$#intermediate_dirs) {
        my $intdir = $intermediate_dirs[$i];
        my @dirs;
        if ($i == 0) {
            # first path elem, we search starting_path first since
            # candidate_paths is still empty.
            @dirs = ($starting_path);
        } else {
            # subsequent path elem, we search all candidate_paths
            @dirs = @candidate_paths;
        }

        if ($i == $#intermediate_dirs && $intdir eq '') {
            @candidate_paths = @dirs;
            last;
        }

        my @new_candidate_paths;
        for my $dir (@dirs) {
            #say "D:  intdir list($dir)";
            my $listres = $list_func->($dir, $intdir, 1);
            next unless $listres && @$listres;
            # check if the deeper level is a candidate
            my $re = do {
                my $s = $intdir;
                $s =~ s/_/-/g if $map_case;
                $exp_im_path ?
                    ($ci ? qr/\A\Q$s/i : qr/\A\Q$s/) :
                        ($ci ? qr/\A\Q$s\E(?:\Q$path_sep\E)?\z/i :
                             qr/\A\Q$s\E(?:\Q$path_sep\E)?\z/);
            };
            #say "D:  re=$re";
            for (@$listres) {
                #say "D:  $_";
                my $s = $_; $s =~ s/_/-/g if $map_case;
                #say "D: <$s> =~ $re";
                next unless $s =~ $re;
                my $p = $dir =~ m!\A\z|\Q$path_sep\E\z! ?
                    "$dir$_" : "$dir$path_sep$_";
                push @new_candidate_paths, $p;
            }
        }
        #say "D:  candidate_paths=[",join(", ", map{"<$_>"} @new_candidate_paths),"]";
        return [] unless @new_candidate_paths;
        @candidate_paths = @new_candidate_paths;
    }

    my $cut_chars = 0;
    if (length($starting_path)) {
        $cut_chars += length($starting_path);
        unless ($starting_path =~ /\Q$path_sep\E\z/) {
            $cut_chars += length($path_sep);
        }
    }

    my @res;
    for my $dir (@candidate_paths) {
        #say "D:opendir($dir)";
        my $listres = $list_func->($dir, $leaf, 0);
        next unless $listres && @$listres;
        my $re = do {
            my $s = $leaf;
            $s =~ s/_/-/g if $map_case;
            $ci ? qr/\A\Q$s/i : qr/\A\Q$s/;
        };
        #say "D:re=$re";
        for (@$listres) {
            my $s = $_; $s =~ s/_/-/g if $map_case;
            next unless $s =~ $re;
            my $p = $dir =~ m!\A\z|\Q$path_sep\E\z! ?
                "$dir$_" : "$dir$path_sep$_";
            next if $filter_func && !$filter_func->($p);

            # process into final result
            substr($p, 0, $cut_chars) = '' if $cut_chars;
            $p = "$result_prefix$p" if length($result_prefix);
            unless ($p =~ /\Q$path_sep\E\z/) {
                $p .= $path_sep if $is_dir_func->($p);
            }

            push @res, $p;
        }
    }

    \@res;
}
1;
# ABSTRACT: Complete path

__END__

=pod

=encoding UTF-8

=head1 NAME

Complete::Path - Complete path

=head1 VERSION

This document describes version 0.03 of Complete::Path (from Perl distribution Complete-Path), released on 2014-12-25.

=head1 DESCRIPTION

=head1 FUNCTIONS


=head2 complete_path(%args) -> array

Complete path.

Complete path, for anything path-like. Meant to be used as backend for other
functions like C<Complete::Util::complete_file> or
C<Complete::Module::complete_module>. Provides features like case-insensitive
matching, expanding intermediate paths, and case mapping.

Algorithm is to split path into path elements, listing (using the supplied
C<list_func>) and perform filtering (using the supplied C<filter_func>) at every
level.

Arguments ('*' denotes required arguments):

=over 4

=item * B<ci> => I<bool>

Case-insensitive matching.

=item * B<exp_im_path> => I<bool>

Expand intermediate paths.

This option mimics feature in zsh where when you type something like C<cd
/h/u/b/myscript> and get C<cd /home/ujang/bin/myscript> as a completion answer.

=item * B<filter_func> => I<code>

=item * B<is_dir_func>* => I<code>

Function to check whether a path is a "dir".

=item * B<list_func>* => I<code>

Function to list the content of intermediate "dirs".

Code will be called with arguments: ($path, $cur_path_elem, $is_intermediate).

Code should return an arrayref containing list of elements.

=item * B<map_case> => I<bool>

Treat _ (underscore) and - (dash) as the same.

This is another convenience option like C<ci>, where you can type C<-> (without
pressing Shift, at least in US keyboard) and can still complete C<_> (underscore,
which is typed by pressing Shift, at least in US keyboard).

This option mimics similar option in bash/readline: C<completion-map-case>.

=item * B<path_sep> => I<str> (default: "/")

=item * B<starting_path>* => I<str> (default: "")

=item * B<word> => I<str> (default: "")

=back

Return value:

 (array)

=head1 TODO

Recursive matching, e.g. **/Util to match: List/Util, CHI/Util,
Class/Factory/Util, and so on

=head1 SEE ALSO

L<Complete>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/Complete-Path>.

=head1 SOURCE

Source repository is at L<https://github.com/perlancar/perl-Complete-Path>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=Complete-Path>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
