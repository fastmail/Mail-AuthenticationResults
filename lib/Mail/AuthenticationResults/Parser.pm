package Mail::AuthenticationResults::Parser;
# ABSTRACT: Class for parsing Authentication Results Headers

require 5.008;
use strict;
use warnings;
# VERSION
use Carp;

use Mail::AuthenticationResults::Header;
use Mail::AuthenticationResults::Header::AuthServID;
use Mail::AuthenticationResults::Header::Comment;
use Mail::AuthenticationResults::Header::Entry;
use Mail::AuthenticationResults::Header::SubEntry;
use Mail::AuthenticationResults::Header::Version;

use Mail::AuthenticationResults::Token::Assignment;
use Mail::AuthenticationResults::Token::Comment;
use Mail::AuthenticationResults::Token::QuotedString;
use Mail::AuthenticationResults::Token::Separator;
use Mail::AuthenticationResults::Token::String;

use JSON;

=head1 DESCRIPTION

Class for parsing Authentication Results headers into objects.

takes a string and returns a L<Mail::AuthenticationResults::Header> object

=method new( $header )

Return a new Parser instance.

If $header is supplied then parse it and return the parsed object.

=cut

sub new {
    my ( $class, $auth_header ) = @_;
    my $self = {};
    bless $self, $class;

    if ( $auth_header ) {
        $self->parse( $auth_header );
    }

    return $self;
}

=method parse( $header )

Parse $header and return the parsed object.

=cut

sub parse {
    my ( $self, $header ) = @_;

    $self->tokenise( $header );

    $self->_parse_authservid();

    while ( @{ $self->{ 'tokenised' } } ) {
        $self->_parse_entry();
    }

    return $self->parsed();
}

=method from_authentication_results_json( $json )

Parse $json as the json returned from an as_json method call and return the parsed object.

=cut

sub from_authentication_results_json {
    my ( $self, $json ) = @_;
    my $j = JSON->new();
    my $hashref = $j->decode( $json );
    return $self->_from_hashref( $hashref );
}

sub _from_hashref {
    my ( $self, $hashref ) = @_;
    my $type = $hashref->{'type'};
    my $object
        = $type eq 'header'     ? Mail::AuthenticationResults::Header->new()
        : $type eq 'authservid' ? Mail::AuthenticationResults::Header::AuthServID->new()
        : $type eq 'entry'      ? Mail::AuthenticationResults::Header::Entry->new()
        : $type eq 'subentry'   ? Mail::AuthenticationResults::Header::SubEntry->new()
        : $type eq 'comment'    ? Mail::AuthenticationResults::Header::Comment->new()
        : croak "unknown type $type";

    if ( $type eq 'header' ) {
        my $authserv_id = $self->_from_hashref( $hashref->{ 'authserv_id' } );
        $object->set_value( $authserv_id );
    }
    else {
        $object->set_key( $hashref->{'key'} ) if exists $hashref->{'key'};
        $object->safe_set_value( $hashref->{'value'} ) if exists $hashref->{'value'};
    }

    if ( exists $hashref->{'children'} ) {
        for my $child ( @{ $hashref->{'children'} } ) {
            my $child_object = $self->_from_hashref( $child );
            $object->add_child( $child_object );
        }
    }

    return $object;
}


=method tokenise( $header )

Tokenise the given $header string

=cut

sub tokenise {
    my ( $self, $header ) = @_;

    my @tokenised;

    $header =~ s/\n/ /g;
    $header =~ s/\r/ /g;
    $header =~ s/^\s+//;

    # Remove Header part if present
    if ( $header =~ /^Authentication-Results:/i ) {
        $header =~ s/^Authentication-Results://i;
    }

    my $args = {};
    while ( length($header) > 0 ) {

        my $token;
        $header =~ s/^\s+//;

        my $last_non_comment_type = exists( $args->{ 'last_non_comment_type' } ) ? $args->{ 'last_non_comment_type' }->is() : 'none';

        if ( length( $header ) == 0 ) {
            last;
        }
        elsif ( $header =~ /^\(/ ) {
            $token = Mail::AuthenticationResults::Token::Comment->new( $header, $args );
        }
        elsif ( $header =~ /^;/ ) {
            $token = Mail::AuthenticationResults::Token::Separator->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }
        elsif ( $header =~ /^"/ ) {
            $token = Mail::AuthenticationResults::Token::QuotedString->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }
        elsif ( $last_non_comment_type ne 'assignment' && $header =~ /^\./ ) {
            $token = Mail::AuthenticationResults::Token::Assignment->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }
        elsif ( $last_non_comment_type eq 'assignment' && $header =~ /^\./ ) {
            # a . after an assignment cannot be another assignment, likely an unquoted string.
            $token = Mail::AuthenticationResults::Token::String->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }
        elsif ( $last_non_comment_type ne 'assignment' && $header =~ /^\// ) {
            $token = Mail::AuthenticationResults::Token::Assignment->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }
        elsif ( $last_non_comment_type eq 'assignment' && $header =~ /^\// ) {
            # a / after an assignment cannot be another assignment, likely an unquoted string.
            $token = Mail::AuthenticationResults::Token::String->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }
        elsif ( $header =~ /^=/ ) {
            $token = Mail::AuthenticationResults::Token::Assignment->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }
        else {
            $token = Mail::AuthenticationResults::Token::String->new( $header, $args );
            $args->{ 'last_non_comment_type' } = $token;
        }

        $header = $token->remainder();
        push @tokenised, $token;
    }

    croak 'Nothing to parse' if ! @tokenised;

    $self->{ 'tokenised' } = \@tokenised;

    return;
}

sub _parse_authservid {
    my ( $self ) = @_;
    my $tokenised = $self->{ 'tokenised' };
    my $token;

    my $authserv_id = Mail::AuthenticationResults::Header::AuthServID->new();

    # Find the ServID
    while ( @$tokenised ) {
        $token = shift @$tokenised;
        if ( $token->is() eq 'string' ) {
            $authserv_id->set_value( $token->value() );
            last;
        }
        elsif ( $token->is() eq 'comment' ) {
            $authserv_id->add_child( Mail::AuthenticationResults::Header::Comment->new()->set_value( $token->value() ) );
        }
        else {
            # assignment or separator, both are bogus
            croak 'Invalid AuthServ-ID';
        }
    }

    my $expecting = 'key';
    my $key;

    TOKEN:
    while ( @$tokenised ) {
        $token = shift @$tokenised;

        if ( $token->is() eq 'assignment' ) {
            if ( $expecting eq 'assignment' ) {
                if ( $token->value() eq '=' ) {
                    $expecting = 'value';
                }
                else {
                    croak 'unexpected token';
                }
            }
            else {
                croak 'not expecting an assignment';
            }
        }
        elsif ( $token->is() eq  'comment' ) {
            $authserv_id->add_child( Mail::AuthenticationResults::Header::Comment->new()->set_value( $token->value() ) );
        }
        elsif ( $token->is() eq 'separator' ) {
            last TOKEN;
        }
        if ( $token->is() eq 'string' ) {
            if ( $expecting eq 'key' ) {
                $key = $token;
                $expecting = 'assignment';
            }
            elsif ( $expecting eq 'value' ) {
                $authserv_id->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( $key->value() )->set_value( $token->value() ) );
                $expecting = 'key';
                undef $key;
            }
            else {
                croak 'not expecting a string';
            }
        }

    }
    if ( $expecting ne 'key' ) {
        if ( $key->value() =~ /^[0-9]+$/ ) {
            # Looks like a version
            $authserv_id->add_child( Mail::AuthenticationResults::Header::Version->new()->set_value( $key->value() ) );
        }
        else {
            # Probably bogus, but who knows!
            $authserv_id->add_child( Mail::AuthenticationResults::Header::SubEntry->new()->set_key( $key->value() ) );
        }
    }

    $self->{ 'header' } = Mail::AuthenticationResults::Header->new()->set_value( $authserv_id );
    $self->{ 'tokenised' } = $tokenised;

    return;
}

sub _parse_entry {
    my ( $self ) = @_;
    my $tokenised = $self->{ 'tokenised' };

    my $entry = Mail::AuthenticationResults::Header::Entry->new();
    my $working_on = $entry;

    my $expecting = 'key';
    my $is_subentry = 0;
    TOKEN:
    while ( @$tokenised ) {
        my $token = shift @$tokenised;

        if ( $token->is() eq 'assignment' ) {
            if ( $expecting eq 'assignment' ) {
                if ( $token->value() eq '=' ) {
                    $expecting = 'value';
                }
                elsif ( $token->value() eq '.' ) {
                    $expecting = 'keymod';
                }
                elsif ( $token->value() eq '/' ) {
                    $expecting = 'version';
                }
            }
            else {
                croak 'not expecting an assignment';
            }
        }
        elsif ( $token->is() eq  'comment' ) {
            $working_on->add_child( Mail::AuthenticationResults::Header::Comment->new()->set_value( $token->value() ) );
        }
        elsif ( $token->is() eq 'separator' ) {
            last TOKEN;
        }
        if ( $token->is() eq 'string' ) {
            if ( $expecting eq 'key' ) {
                if ( ! $is_subentry ) {
                    if ( $token->value() eq 'none' ) {
                        # Special case the none
                        $expecting = 'no_more_after_none';
                    }
                    else {
                        $entry->set_key( $token->value() );
                        $expecting = 'assignment';
                    }
                }
                else {
                    $working_on = Mail::AuthenticationResults::Header::SubEntry->new()->set_key( $token->value() );
                    $expecting = 'assignment';
                }
            }
            elsif ( $expecting eq 'keymod' ) {
                $working_on->set_key( $working_on->key() . '.' . $token->value() );
                $expecting = 'assignment';
            }
            elsif ( $expecting eq 'version' ) {
                if ( $token->value() =~ /^[0-9]+$/ ) {
                    # Looks like a version
                    $working_on->add_child( Mail::AuthenticationResults::Header::Version->new()->set_value( $token->value() ) );
                }
                else {
                    croak 'bad version token';
                }
                $expecting = 'assignment';
            }
            elsif ( $expecting eq 'value' ) {
                if ( ! $is_subentry ) {
                    $entry->set_value( $token->value() );
                    $is_subentry = 1;
                }
                else {
                    $entry->add_child( $working_on->set_value( $token->value() ) );
                }
                $expecting = 'key';
            }
            else {
                croak 'not expecting a string';
            }
        }

    }

    if ( $expecting eq 'no_more_after_none' ) {
        $self->{ 'tokenised' } = $tokenised;
        # We may have comment entries, if so add those to the header object
        foreach my $child ( @{ $entry->children() } ) {
            delete $child->{ 'parent' };
            $self->{ 'header' }->add_child( $child );
        }
        return;
    }

    if ( $expecting ne 'key' ) {
        if ( $is_subentry ) {
            $entry->add_child( $working_on );
        }
    }

    $self->{ 'header' }->add_child( $entry );
    $self->{ 'tokenised' } = $tokenised;

    return;
}

=method parsed()

Return the parsed object tree

=cut

sub parsed {
    my ( $self ) = @_;
    return $self->{ 'header' };
}

1;
