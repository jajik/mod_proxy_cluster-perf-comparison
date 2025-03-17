#!/usr/bin/perl

use v5.32;
use warnings;

use File::Basename;
use List::Util qw( max sum );
use List::MoreUtils qw( uniq );

sub parse_record {
    my $filename = shift;
    my $fh = open(my $file, "<", $filename) || die "Can't open $filename";
    my %db;
    my $curr = undef;
    
    while (my $line = <$file>) {
        chomp $line;
        if ($line =~ m/url:/) {
            next;
        } elsif ($line =~ m/statuses:/) {
            $curr = \%{$db{status}};
            next;
        } elsif ($line =~ m/errors:/) {
            $curr = \%{$db{error}};
            next;
        } elsif ($line =~ m/avg:/) {
            $line =~ s/:\s*/:/g;
            my @r = split / /, $line;
            for my $kv (@r) {
                my ($k, $v) = split /:/, $kv;
                $db{response}{$k} = $v;
            }
            next;
        } elsif ($line =~ m/distribution:/) {
            $curr = \%{$db{distribution}};
            next;
        }
    
        if (defined $curr) {
            $line =~ s/\s*//g;
            my ($k, $v) = split /:/, $line;
            $curr->{$k} = $v;
        }
    }
    return \%db;
}

sub create_table {
    my ($data) = @_;

    my %table;
    my @files = keys %$data;
    my @versions, my @statuses, my @responses, my @errors;

    foreach my $f (@files) {
        push @versions, keys %{$data->{$f}};
    }
    @versions = uniq @versions;

    foreach my $f (@files) {
        foreach my $v (@versions) {
            push @statuses, keys %{$data->{$f}{$v}{status}};
            push @responses, keys %{$data->{$f}{$v}{response}};
            push @errors, keys %{$data->{$f}{$v}{error}};
        }
    }

    @statuses = uniq @statuses;
    @responses = uniq @responses;
    @errors = uniq @errors;

    foreach my $stat (@statuses) {
        my $header = "Status $stat";
        my %rec;
        foreach my $f (@files) {
            foreach my $v (@versions) {
                $rec{$f}{$v} = $data->{$f}{$v}{status}->{$stat};
            }
        }
        $table{$header} = \%rec;
    }

    foreach my $resp (@responses) {
        my $header = "Response $resp";
        my %rec;
        foreach my $f (@files) {
            foreach my $v (@versions) {
                $rec{$f}{$v} = $data->{$f}{$v}{response}->{$resp};
            }
        }
        $table{$header} = \%rec;
    }

    foreach my $err (@errors) {
        my $header = "Error $err";
        my %rec;
        foreach my $f (@files) {
            foreach my $v (@versions) {
                $rec{$f}{$v} = $data->{$f}{$v}{error}->{$err};
            }
        }
        $table{$header} = \%rec;
    }

    foreach my $f (@files) {
        foreach my $v (@versions) {
            my @nodes = keys %{$data->{$f}{$v}{distribution}};
            # if TOMCAT_COUNT is not defined, use @nodes count, but that probably
            # will lead to inaccurate results if no traffic went to any node...
            my $dist_count = $ENV{TOMCAT_COUNT} || @nodes;

            if (@nodes == 0 || $dist_count <= 1) {
                next;
            }

            if (!$ENV{TOMCAT_COUNT}) {
                warn "The distribution rely on number nodes in data. This may lead to unreliable results. (TOMCAT_COUNT not defined)"
            }

            my $dist_sum = sum (map { $data->{$f}{$v}{distribution}{$_} } @nodes);

            my $dist_mean = $dist_sum / $dist_count;
            my $dist_variance = 0;
            for (my $i = 0; $i < $dist_count; $i++) {
                # for nodes missing in the distribution it's 0
                my $d = 0;
                if ($i < @nodes) {
                    $d = $data->{$f}{$v}{distribution}{$nodes[$i]};
                }
                $dist_variance += ($d - $dist_mean) ** 2 / ($dist_count - 1);
            }

            $table{"Distribution mean"}{$f}{$v} = sprintf("%.1f", $dist_mean);
            $table{"Distribution variance"}{$f}{$v} = sprintf("%.1f", $dist_variance);
        }
    }

    return \%table;
}

sub print_table_header {
    my @arr = @_;
    foreach my $h (@arr) {
        print "| $h "
    }
    say "|";
    foreach my $h (@arr) {
        my $len = length $h;
        print "| ", '-' x $len, " ";
    }
    say "|";
}

sub print_table {
    my ($tb, $vs) = @_;

    my @header = sort { if ($a =~ m/Status/ && $b =~ m/Status/) { $a cmp $b } else { $b cmp $a } } (keys %$tb);
    my @files = sort (keys %{$tb->{$header[0]}});
    my @versions = sort @$vs;

    my $vlen = max(map length, @versions);
    my $version_padded = 'Version' . (' ' x ($vlen > 7 ? $vlen - 7 : 0));
    $vlen = length $version_padded;

    my $flen = max(map length, @files);
    my $file_padded = 'Source' . (' ' x ($flen > 6 ? $flen - 6 : 0));
    $flen = length $file_padded;

    print_table_header ($file_padded, $version_padded, @header);

    foreach my $f (@files) {
        my $displayed_filename = $f;
        foreach my $v (@versions) {

            printf "| %${flen}s ", $displayed_filename;
            $displayed_filename = ""; # a little hack, but it improves readability imho

            printf "| %${vlen}s ", $v;

            foreach my $h (@header) {
                my $len = length $h;
                printf "| %${len}s ", defined $tb->{$h}{$f}{$v} ? $tb->{$h}{$f}{$v} : ' ' x $len;
            }
            say "|";
        }
        say "-";
    }
}

sub print_results {
    my $data = shift;

    # get all gathered filenames
    my @files = keys %$data;
    # get all versions
    my @versions;
    for my $f (@files) {
        push @versions, keys %{$data->{$f}};
    }
    @versions = uniq @versions;

    # go through files and create a table for every single one
    my $table = create_table $data;
    if (keys %$table >= 3) {
        print_table $table, \@versions;
    } else {
        say "Something went wrong while parsing the data";
    }
}


my %result;

# Process all given directories
foreach my $arg (@ARGV) {
    say "for $arg\n------------------";
    my @dirs = glob "$arg/*";
    foreach my $version_dir (@dirs) {
        my @files = glob "$version_dir/client-run*";
        foreach my $f (@files) {
            $result{basename $f}{basename $version_dir} = parse_record $f;
        }
    }
}

print_results \%result;

