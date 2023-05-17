=head1 NAME

EPrints::Plugin::Screen::ManageArkivum

=cut

package EPrints::Plugin::Screen::ManageArkivum;

use EPrints::Plugin::Screen;
use CGI;
use Data::Dumper;


@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
    my( $class, %params ) = @_;

    my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ report /];

    $self->{appears} = [
        {
			place => "arkivum_transaction_actions",
			position => 100,
            action => "report"
		},
    ];

    return $self;
}

sub allow_report
{
	my( $self ) = @_;
    print STDERR "Hello\n";
	my $repo = $self->{repository};
	my $current_user = $self->{repository}->current_user;
    #my $screenid = $self->{processor}->{screenid};

    #if( $screenid eq "Items" && EPrints::Utils::is_set( $current_user->value( "orcid" ) ) ) #manage deposits screen
    #{
		#has the current user given permission?
        #	return 1;
        #}

    #my $dataset = $self->{repository}->param( "dataset" );
    return 1;
}

sub action_report
{
	my( $self ) = @_;

}

sub properties_from
{
    my( $self ) = @_;

    $self->SUPER::properties_from;


}
