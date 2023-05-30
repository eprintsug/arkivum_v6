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

	$self->{actions} = [qw/ report restore_to_local request_deletion /];

    $self->{appears} = [
        {
			place => "arkivum_transaction_actions",
			position => 100,
            action => "report"
		},
        {
			place => "arkivum_transaction_actions",
			position => 200,
            action => "restore_to_local"
		},
        {
			place => "arkivum_transaction_actions",
			position => 300,
            action => "request_deletion"
		},
    ];

    return $self;
}

sub properties_from
{
    my( $self ) = @_;

    my $repo = $self->{repository};

    $self->{processor}->{eprintid} = $repo->param( "eprintid" );
 
    my $eprint_ds = $repo->dataset( "eprint" );
    $self->{processor}->{eprint} = $eprint_ds->dataobj( $repo->param( "eprintid" ) );

    my $arkivum_ds = $repo->dataset( "arkivum" );
    $self->{processor}->{ark_t} = $arkivum_ds->dataobj( $repo->param( "arkivumid" ) );
}

sub allow_report
{
	my( $self ) = @_;

    # you can always request a new report...
    return 1;
}

sub action_report
{
	my( $self ) = @_;

    my $repo = $self->{repository};

    # Then start the monitor event
    my $monitor_event = EPrints::DataObj::EventQueue->create_unique( $repo, {
        pluginid => "Event::ArkivumV6",
        action => "ingest_report",
        params => [$self->{processor}->{ark_t}->value("ingestid"), $self->{processor}->{ark_t}->id],
    });

    $self->add_result_message( "report" );
}

sub allow_restore_to_local
{
	my( $self ) = @_;

    my $repo = $self->{repository};

    my $eprintid = $self->{eprintid} || $repo->param( "eprintid" );
    my $eprint_ds = $repo->dataset( "eprint" );
    my $eprint = $eprint_ds->dataobj( $eprintid );

    return 0 if !defined $eprint;

    my $arkivumid = $self->{arkivumid} || $repo->param( "arkivumid" );
    my $arkivum_ds = $repo->dataset( "arkivum" );
    my $ark_t = $arkivum_ds->dataobj( $arkivumid );

    return 0 if !defined $ark_t;

    # If we are here we have the latest version of the archiveed eprint and it is THE SAME (according to significant metadata) as the current eprint
    my $result = $ark_t->value("archive_fingerprint") eq $ark_t->take_fingerprint($eprint);

    return $ark_t->value("archive_fingerprint") eq $ark_t->take_fingerprint($eprint);
}

sub action_restore_to_local
{
	my( $self ) = @_;

    $self->add_result_message( "restore" );
}

sub allow_request_deletion
{
	my( $self ) = @_;

    # TO DO!!!
    return 0;
}

sub action_request_deletion
{
	my( $self ) = @_;
   
    $self->add_result_message( "deletion" );
}

sub add_result_message
{
    my( $self, $message ) = @_;

    if( $message )
    {
        $self->{processor}->add_message( "message",
            $self->html_phrase( $message ) );
    }
    else
    {
        # Error?
        $self->{processor}->add_message( "error" );
    }

    $self->{processor}->{screenid} = "EPrint::View";
}
