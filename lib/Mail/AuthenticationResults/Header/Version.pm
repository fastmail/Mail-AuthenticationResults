package Mail::AuthenticationResults::Header::Version;
# ABSTRACT: Class modelling the AuthServID part of the Authentication Results Header

require 5.008;
use strict;
use warnings;
# VERSION
use Scalar::Util qw{ weaken };
use Carp;

use base 'Mail::AuthenticationResults::Header::Base';

=head1 DESCRIPTION

A version string, this may be associated with an AuthServID, Entry, Group, or SubEntry.

Please see L<Mail::AuthenticationResults::Header::Base>

=cut

sub _HAS_VALUE{ return 1; }

sub as_string {
    my ( $self ) = @_;

    if ( ! $self->value() ) {
        return q{};
    }

    my $string = q{};

    if ( ref $self->parent() ne 'Mail::AuthenticationResults::Header::AuthServID' ) {
        $string = '/ ';
    }

    $string .= $self->value();

    return $string;
}

sub safe_set_value {
    my ( $self, $value ) = @_;

    $value = 1 if ! defined $value;
    $value =~ s/[^0-9]//g;
    $value = 1 if $value eq q{};

    $self->set_value( $value );
    return $self;
}

sub set_value {
    my ( $self, $value ) = @_;

    croak 'Does not have value' if ! $self->_HAS_VALUE(); # uncoverable branch true
    # HAS_VALUE is 1 for this class
    croak 'Value cannot be undefined' if ! defined $value;
    croak 'Value must be numeric' if $value =~ /[^0-9]/;

    $self->{ 'value' } = $value;
    return $self;
}

1;
