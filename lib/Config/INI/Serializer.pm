use strict;
use warnings;
package Config::INI::Serializer;

# ABSTRACT: Round-trip INI serializer for nested data

=head1 ABOUT

This library is the carved-out INI-file handling from
L<App::Context|App::Context>, namely the essential functions from
L<App:Serializer::Ini|App:Serializer::Ini> and
L<App::Reference|App::Reference>.

I<O NOES - JET ANOTHR INI MOTULE!> - but this one turned out to work
better with INI-like data serialization in mind where compatibility
with other modules is not as important, like I needed for the
L<dpath|App::DPath> utility.

=head1 AUTHOR

=over 4

=item Stephen Adkins, original code in L<App:Serializer::Ini|App::Serializer::Ini>.

=item Steffen Schwigon, carved out into separate module to have a lightweight dependency.

=head1 SYNOPSIS

=over 4

=item Data to INI

 require Config::INI::Serializer;
 my $ini = Config::INI::Serializer->new;
 $data   = { an         => 'arbitrary',
             collection => [ 'of', 'data', ],
             of         => {
                            arbitrary => 'depth',
                           },
           };
 my $ini_text = $ini->serialize($data);

=item INI to Data

 require Config::INI::Serializer;
 my $ini  = Config::INI::Serializer->new;
 my $data = $ini->deserialize($ini_text);

=back

=head1 CAVEATS

=over 4

=item It is quite for sure a non-standard variant of INI.

It can read most of the other INI formats, too, but writes out a bit
special to handle nested data. 

So using this module is kind of a "one-way ticket to slammertown with
no return ticket" aka. vendor lock-in.

=item It does not handle multiline values correctly.

They will written out straight like this

 key1 = This will be
 some funky multi line
 entry
 key2 = foo

but on reading you will only get C<key = This will be>.

It does not choke on the additional lines, though, as ong as they
don't contain a C<=> character.

=back

=method serialize

=over 4

=item Signature: $inidata = $serializer->serialize($data);

=item Param: $data (ref)

=item Return: $inidata (text)

=item Sample Usage:

    $serializer = Config::INI::Serializer->new;
    $inidata = $serializer->serialize($data);

=back

=method deserialize

=over 4

=item Signature: $data = $serializer->deserialize($inidata);

=item Param: $inidata (text)

=item Return: $data (ref)

=item Sample Usage:

    $serializer = Config::INI::Serializer->new;
    $data = $serializer->deserialize($inidata);
    print $serializer->dump($data), "\n";

=back


=cut

# lightweight OO to the extreme, as we really don't need more
sub new {
        bless {}, shift;
}

#############################################################################
# _get_branch()
#############################################################################

# utility function, stolen from App::Reference, made internal here

sub _get_branch {
    my ($self, $branch_name, $create, $ref) = @_;
    my ($sub_branch_name, $branch_piece, $attrib, $type, $branch, $cache_ok);
    $ref = $self if (!defined $ref);

    # check the cache quickly and return the branch if found
    $cache_ok = (ref($ref) ne "ARRAY" && $ref eq $self); # only cache from $self
    $branch = $ref->{_branch}{$branch_name} if ($cache_ok);
    return ($branch) if (defined $branch);

    # not found, so we need to parse the $branch_name and walk the $ref tree
    $branch = $ref;
    $sub_branch_name = "";

    # these: "{field1}" "[3]" "field2." are all valid branch pieces
    while ($branch_name =~ s/^([\{\[]?)([^\.\[\]\{\}]+)([\.\]\}]?)//) {

        $branch_piece = $2;
        $type = $3;
        $sub_branch_name .= ($3 eq ".") ? "$1$2" : "$1$2$3";

        if (ref($branch) eq "ARRAY") {
            if (! defined $branch->[$branch_piece]) {
                if ($create) {
                    $branch->[$branch_piece] = ($type eq "]") ? [] : {};
                    $branch = $branch->[$branch_piece];
                    $ref->{_branch}{$sub_branch_name} = $branch if ($cache_ok);
                }
                else {
                    return(undef);
                }
            }
            else {
                $branch = $branch->[$branch_piece];
                $sub_branch_name .= "$1$2$3";   # accumulate the $sub_branch_name
            }
        }
        else {
            if (! defined $branch->{$branch_piece}) {
                if ($create) {
                    $branch->{$branch_piece} = ($type eq "]") ? [] : {};
                    $branch = $branch->{$branch_piece};
                    $ref->{_branch}{$sub_branch_name} = $branch if ($cache_ok);
                }
                else {
                    return(undef);
                }
            }
            else {
                $branch = $branch->{$branch_piece};
            }
        }
        $sub_branch_name .= $type if ($type eq ".");
    }
    return $branch;
}

# utility function, stolen from App::Reference, made internal here
sub _set {
    my ($self, $property_name, $property_value, $ref) = @_;
    #$ref = $self if (!defined $ref);

    my ($branch_name, $attrib, $type, $branch, $cache_ok);
    if ($property_name =~ /^(.*)([\.\{\[])([^\.\[\]\{\}]+)([\]\}]?)$/) {
        $branch_name = $1;
        $type = $2;
        $attrib = $3;
        $cache_ok = (ref($ref) ne "ARRAY" && $ref eq $self);
        $branch = $ref->{_branch}{$branch_name} if ($cache_ok);
        $branch = $self->_get_branch($1,1,$ref) if (!defined $branch);
    }
    else {
        $branch = $ref;
        $attrib = $property_name;
    }

    if (ref($branch) eq "ARRAY") {
        $branch->[$attrib] = $property_value;
    }
    else {
        $branch->{$attrib} = $property_value;
    }
}

sub serialize {
    my ($self, $data) = @_;
    $self->_serialize($data, "");
}

sub _serialize {
    my ($self, $data, $section) = @_;
    my ($section_data, $idx, $key, $elem);
    if (ref($data) eq "ARRAY") {
        for ($idx = 0; $idx <= $#$data; $idx++) {
            $elem = $data->[$idx];
            if (!ref($elem)) {
                $section_data .= "[$section]\n" if (!$section_data && $section);
                $section_data .= "$idx = $elem\n";
            }
        }
        for ($idx = 0; $idx <= $#$data; $idx++) {
            $elem = $data->[$idx];
            if (ref($elem)) {
                $section_data .= $self->_serialize($elem, $section ? "$section.$idx" : $idx);
            }
        }
    }
    elsif (ref($data)) {
        foreach $key (sort keys %$data) {
            $elem = $data->{$key};
            if (!ref($elem)) {
                no warnings 'uninitialized';
                $section_data .= "[$section]\n" if (!$section_data && $section);
                $section_data .= "$key = $elem\n";
            }
        }
        foreach $key (sort keys %$data) {
            $elem = $data->{$key};
            if (ref($elem)) {
                $section_data .= $self->_serialize($elem, $section ? "$section.$key" : $key);
            }
        }
    }

    return $section_data;
}

sub deserialize {
    my ($self, $inidata) = @_;
    my ($data, $r, $line, $attrib_base, $attrib, $value);

    $data = {};

    $attrib_base = "";
    foreach $line (split(/\n/, $inidata)) {
        next if ($line =~ /^;/);  # ignore comments
        next if ($line =~ /^#/);  # ignore comments
        if ($line =~ /^\[([^\[\]]+)\] *$/) {  # i.e. [Repository.default]
            $attrib_base = $1;
        }
        if ($line =~ /^ *([^ =]+) *= *(.*)$/) {
            $attrib = $attrib_base ? "$attrib_base.$1" : $1;
            $value = $2;
            $self->_set($attrib, $value, $data);
        }
    }
    return $data;
}

# END stolen ::App::Serialize::Ini

1;
