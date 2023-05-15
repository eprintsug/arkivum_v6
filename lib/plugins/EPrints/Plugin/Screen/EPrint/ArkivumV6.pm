package EPrints::Plugin::Screen::EPrint::ArkivumV6;

our @ISA = ( 'EPrints::Plugin::Screen::EPrint' );

use strict;
use Data::Dumper;

sub new
{
  my( $class, %params ) = @_;
  
  my $self = $class->SUPER::new(%params);

  $self->{actions} = [qw/ report reingest restore_to_local request_deletion/];

  $self->{appears} = [
    {
      place => "eprint_view_tabs",
      position => 6000,
    },
  ];

  #avoid issues with multiple archives under <v3.3.13
  $self->{disable} = 0;

  return $self;
}

sub can_be_viewed
{
  my( $self ) = @_;
  #    my $repo = $self->{repository};
  return $self->allow( "eprint/arkivum" );
}
# Overriding allow_action so we can pass through params
sub allow_action
{
	my( $self, $action_id, %params ) = @_;
	my $ok = 0;
	foreach my $an_action ( @{$self->{actions}} )
	{
		if( $an_action eq $action_id )
		{
			$ok = 1;
			last;
		}
	}

	return( 0 ) if( !$ok );

	my $fn = "allow_".$action_id;
	return $self->$fn(%params);
}

sub render
{
  my( $self ) = @_;

  my $repo = $self->{repository};
  my $page = $repo->xml->create_element( "div" ); # wrapper

  my $eprint = $self->{processor}->{eprint};

  $page->appendChild( $repo->xml->create_element( "br" ) );
 
  $page->appendChild(my $h2 = $repo->make_element("h2") );
  $h2->appendChild($repo->make_text("Arkivum transactions for "));
  $h2->appendChild($eprint->render_value("title"));


  my $arkivum_transactions = EPrints::DataObj::Arkivum->search_by_eprintid( $repo, $eprint->id );
  my $ind=0;
  $arkivum_transactions->map(sub {
    my ($session, undef, $ark_t) = @_;

    if($self->allow_reingest(arkivumid=>$ark_t->id, is_not_latest=>$ind)){ #we only expect this when $ind == 0 and there has been a change in the eprint since last archive.
      my $form = $self->render_form( "get" ) ;
      $form->appendChild( $repo->render_hidden_field( "class", $ark_t->get_dataset_id ) );
      $form->appendChild( $repo->render_hidden_field( "arkivumid", $ark_t->id ) );
      $form->appendChild( $repo->render_hidden_field( "is_not_latest", $ind ) );
      $form->appendChild( $repo->render_action_buttons( reingest=>$repo->phrase( "Plugin/Screen/EPrint/ArkivumV6/action_reingest:title" ) ) );
      $page->appendChild( $repo->render_message( "warning", $repo->html_phrase( "arkivum:archive_mismatch", reingest_button=>$form ) ) );
    }
    $page->appendChild( $self->render_arkivum_transaction($ark_t, $ind) );
    $ind++;
  });
 
  return $page;
}

sub render_arkivum_transaction
{
  my( $self, $ark_t, $ind ) = @_;

  my $repo = $self->{repository};
  my $eprint = $self->{processor}->{eprint};
  my $ul = $repo->xml->create_element( "ul" ); # wrapper

  #  my $doc = $repo->get_dataset("document")->dataobj($ark_t->value("docid")) if $ark_t->is_set("docid");
  $eprint = $repo->get_dataset("eprint")->dataobj($ark_t->value("eprintid")) if $ark_t->is_set("eprintid");

  my $frag = $repo->make_doc_fragment;
  my $div = $repo->make_element( "div", class => "arkivum_document" );

  my $status_info = $frag->appendChild( $repo->make_element( "div", class=>"ep_arkivum_view_panel" ) );
  #  $status_info->appendChild( $self->render_eprint_report($ark_t,$eprint,$ind) );

  my $arkivum_status = $ark_t->stepwise_arkivum_status;
  #  $content->appendChild($ark_t->render_citation("default", arkivum_status=>$arkivum_status));
  $status_info->appendChild($ark_t->render_citation("default", 
    arkivum_status=>$arkivum_status, 
    arkivumid => [$ark_t->id,"STRING"],
    eprint_revision => [$ark_t->value("eprint_revision"),"STRING"],
    timestamp => [$ark_t->value("timestamp"),"STRING"],
    arkivum_actions=>[$self->render_arkivum_actions($ark_t,$ind),"XHTML"],
    transaction_index => [$ind,"INTEGER"],
   ));

  return $frag;
}


sub render_eprint_title_summary
{

  my( $self, $ark_t, $eprint, $field ) = @_;

  my $repo = $self->{repository};

  my $frag = $repo->make_doc_fragment;

  $frag->appendChild(
    $repo->html_phrase("Plugin/Screen/EPrint/ArkivumV6/render_eprint_report:title", 
      eprint=>$eprint->render_value("title")
    )
  );

  $frag->appendChild(
    EPrints::DataObj::Arkivum::render_arkivum_status_summary(
      $repo,$field,$ark_t->value("arkivum_status"),undef,undef,$ark_t)
  );

  return $frag;
}

sub render_title_summary
{

  my( $self, $ark_t, $doc, $field ) = @_;

  my $repo = $self->{repository};

  my $frag = $repo->make_doc_fragment;
  print STDERR "#### In render_title_summary...\n";
  $frag->appendChild(
    $repo->html_phrase("Plugin/Screen/EPrint/ArkivumV6/render_report:title", 
      doc=>$doc->render_value("main")
    )
  );

  $frag->appendChild(
    EPrints::DataObj::Arkivum::render_arkivum_status_summary(
      $repo,$field,$ark_t->value("arkivum_status"),undef,undef,$ark_t)
  );

  return $frag;
}

sub allow_report
{
    my( $self, %params ) = @_;

    return 1;     
}

sub allow_reingest
{
  my( $self, %params ) = @_;

  my $repo = $self->{repository};
  
  print STDERR "#### In allow reingest\n";

  return undef if $params{is_not_latest}; # we will refuse to offer reingest when ; # we will refuse to offer reingest when delaing with older archived versionsdelaing with older archived versions
  print STDERR "#### I know if I'm the latest\n";

  return undef if ( !defined $repo );
  print STDERR "#### I have the repo\n";

  my $arkivumid = $params{arkivumid};
  $arkivumid = $self->{session}->param("arkivumid") if !defined $arkivumid;
  
  my $ark_t = $repo->dataset("arkivum")->dataobj( $arkivumid );
  return undef if ( !defined $ark_t );

  my $eprint = $repo->dataset("eprint")->dataobj( $ark_t->value("eprintid") );
  return undef if ( !defined $eprint );
  print STDERR "#### I have the eprint\n";

  #If we are here we have the latest version of the archiveed eprint and it is DIFFERENT (according to significant metadata) to the current eprint
  print STDERR "#### final condition.....\n";
  print STDERR "#### ".$ark_t->value("archive_fingerprint")." ne ".$ark_t->take_fingerprint($eprint)."\n";
  return $ark_t->value("archive_fingerprint") ne $ark_t->take_fingerprint($eprint);

}

sub allow_restore_to_local
{
  my( $self, %params ) = @_;

  my $repo = $self->{repository};

  return undef if $params{is_not_latest}; # we will refuse to offer reingest when ; # we will refuse to offer reingest when delaing with older archived versionsdelaing with older archived versions
  return undef if ( !defined $repo );
  my $ark_t = $repo->dataset("arkivum")->dataobj( $params{arkivumid} );
  return undef if ( !defined $ark_t );
  my $eprint = $repo->dataset("eprint")->dataobj( $ark_t->value("eprintid") );
  return undef if ( !defined $eprint );
  #If we are here we have the latest version of the archiveed eprint and it is THE SAME (according to significant metadata) as the current eprint
  return $ark_t->value("archive_fingerprint") eq $ark_t->take_fingerprint($eprint);
}

sub allow_request_deletion
{
    my( $self, %params ) = @_;

    return 0; 
}


sub render_arkivum_actions
{
  my( $self, $ark_t, $is_not_latest ) = @_;

  my $repo = $self->{repository};

  my $arkivum_actions = $repo->make_element( "div", class=> "arkivum_actions" );

  my $form = $arkivum_actions->appendChild( $self->render_form( "get" ) );
  $form->appendChild( $repo->render_hidden_field( "class", $ark_t->get_dataset_id ) );
  $form->appendChild( $repo->render_hidden_field( "arkivumid", $ark_t->id ) );

  my $order =[];
  my %buttons = {};
	foreach my $action ( @{$self->{actions}} )
	{
    #reingest s a special case and not really associated to a transaction so we won't include in the actions 
    next if $action eq "reingest";
		next if !$self->allow_action( $action, arkivumid=>$ark_t->id, is_not_latest=>$is_not_latest);
		push @{$order}, $action;
		$buttons{$action} = $repo->phrase( "Plugin/Screen/EPrint/ArkivumV6/action_$action:title" );
	}
  $form->appendChild( $repo->render_action_buttons( _order => $order, %buttons ) );

  return $arkivum_actions;
}

sub action_report
{
  my( $self ) = @_;

  my $repo = $self->{repository};

  return undef if ( !defined $repo );

  # get the dataobj we want to update
  my $class = $repo->param( "class" );
  my $dataset = $repo->dataset( $class );
  my $ark_t = $dataset->dataobj( $repo->param( "arkivumid" ) );
  return undef if ( !defined $ark_t );

  # Then start the monitor event
  my $monitor_event = EPrints::DataObj::EventQueue->create_unique( $repo, {
    pluginid => "Event::ArkivumV6",
    action => "ingest_report",
    params => [$ark_t->value("ingestid"), $ark_t->id],
  });
 
  $ark_t->set_value("eventid",$monitor_event->{data}->{eventqueueid});
  $ark_t->commit;

  $self->add_result_message( "report" );
} 

sub action_reingest
{
  my( $self ) = @_;

  my $repo = $self->{repository};

  print STDERR "############### action_reingest: ".$self."\n";

  return undef if ( !defined $repo );

  # get the dataobj we want to update
  my $class = $repo->param( "class" );
  #  my $dataset = $repo->dataset( $class );
  #my $ark_t = $dataset->dataobj( $repo->param( "arkivumid" ) );
  my $eprint = $repo->dataset("eprint")->dataobj($repo->param( "eprintid" ));

  return undef if ( !defined $eprint );

  my $ark_t = $repo->dataset( "arkivum" )->create_dataobj(
  {
      eprintid => $eprint->id,
      userid => $repo->current_user->id,
      arkivum_status => '{"message": "archive_scheduled"}',
  });

  # The arkivum dataobject will take and store a fingerprint from the eprint
  $ark_t->set_value("archive_fingerprint",$ark_t->take_fingerprint($eprint));
  $ark_t->set_value("eprint_revision",$eprint->get_value("rev_number"));
  $ark_t->set_value("timestamp",EPrints::Time::get_iso_timestamp);

  my $ingest_event = EPrints::DataObj::EventQueue->create_unique( $repo, {
      pluginid => "Event::ArkivumV6",
      action => "ingest_eprint",
      params => [$eprint->id, $ark_t->id],
  });


  if(defined $ingest_event){
    $ark_t->set_value("eventid",$ingest_event->{data}->{eventqueueid});
    $ark_t->commit;
  }

   $self->add_result_message( "reingest" );
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

1;
