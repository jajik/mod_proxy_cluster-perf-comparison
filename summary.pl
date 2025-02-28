#!/usr/bin/perl

use v5.32;
use warnings;

use File::Basename;
use List::Util qw( max );
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
    my ($data, $filename) = @_;

    my %table;
    my @versions = keys %$data;
    my @statuses, my @responses, my @errors;

    foreach my $v (@versions) {
        push @statuses, keys %{$data->{$v}{$filename}{status}};
    }
    @statuses = uniq @statuses;

    foreach my $v (@versions) {
        push @responses, keys %{$data->{$v}{$filename}{response}};
    }
    @responses = uniq @responses;

    foreach my $v (@versions) {
        push @errors, keys %{$data->{$v}{$filename}{error}};
    }
    @errors = uniq @errors;

    foreach my $stat (@statuses) {
        my $header = "Status $stat";
        my %rec;
        foreach my $v (@versions) {
            $rec{$v} = $data->{$v}{$filename}{status}->{$stat};
        }
        $table{$header} = \%rec;
    }

    foreach my $resp (@responses) {
        my $header = "Response $resp";
        # my $maxlen = length $header;
        my %rec;
        foreach my $v (@versions) {
            $rec{$v} = $data->{$v}{$filename}{response}->{$resp};
        }
        $table{$header} = \%rec;
    }

    foreach my $err (@errors) {
        my $header = "Error $err";
        my %rec;
        foreach my $v (@versions) {
            $rec{$v} = $data->{$v}{$filename}{error}->{$err};
        }
        $table{$header} = \%rec;
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
    my $tb = shift;

    my @header = sort { if ($a =~ m/Status/ && $b =~ m/Status/) { $a cmp $b } else { $b cmp $a } } (keys %$tb);
    my @versions = sort (keys %{$tb->{$header[0]}});
    my $vlen = max(map length, @versions);

    my $version_padded = 'Version' . (' ' x ($vlen > 7 ? $vlen - 7 : 0));
    $vlen = length $version_padded;

    print_table_header ($version_padded, @header);

    foreach my $v (@versions) {
        printf "| %${vlen}s ", $v;
        foreach my $h (@header) {
            my $len = length $h;
            printf "| %${len}s ", defined $tb->{$h}{$v} ? $tb->{$h}{$v} : ' ' x $len;
        }
        say "|";
    }
}

sub print_results {
    my $data = shift;

    my @versions = keys %$data;
    # get all gathered filenames
    my @files;
    for my $v (@versions) {
        @files = (@files, keys %{$data->{$v}});
    }
    @files = uniq @files;

    # go through files and create a table for every single one
    foreach my $file (sort @files) {
        say "\n## $file";
        my $table = create_table $data, $file;
        if (keys %$table >= 3) {
            print_table $table;
        } else {
            say "Something went wrong while parsing $file";
        }
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
            $result{basename $version_dir}{basename $f} = parse_record $f;
        }
    }
}

print_results \%result;

