package EPrints::Plugin::Screen::EPrint::ArkivumV6;

our @ISA = ( 'EPrints::Plugin::Screen::EPrint' );

use strict;
use Data::Dumper;

sub new
{
  my( $class, %params ) = @_;
  
  my $self = $class->SUPER::new(%params);

  $self->{actions} = [qw/ reingest /];

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
  # my $repo = $self->{repository};
  return $self->allow( "eprint/arkivum" );
}

sub render
{
  my( $self ) = @_;

  my $repo = $self->{repository};
  my $page = $repo->xml->create_element( "div" ); # wrapper

  my $eprint = $self->{processor}->{eprint};

  # get the transactions, if there are any
  my $arkivum_transactions = EPrints::DataObj::Arkivum->search_by_eprintid( $self->{repository}, $self->{processor}->{eprintid} );

  # and save them for later (as properties_from doesn't seem to run in time for eprints view tab screens)
  $self->{processor}->{arkivum_transactions} = $arkivum_transactions;

  $page->appendChild( $repo->xml->create_element( "br" ) );

  # header stuff 
  $page->appendChild(my $h2 = $repo->make_element("h2") );
  $h2->appendChild($repo->make_text("Arkivum transactions for "));
  $h2->appendChild($eprint->render_value("title"));

  # headline action - a reingest
  if( $self->allow_reingest )
  {
    my $form = $self->render_form;
    $form->appendChild( $repo->render_action_buttons(
        _order => [ "reingest" ],
        reingest => $repo->html_phrase( "arkivum_ingest" ),
    ) );

    if( !defined $arkivum_transactions )
    {
      # we have no ingests so far
      $page->appendChild( $repo->render_message( "warning", $repo->html_phrase( "arkivum:first_ingest", reingest_button=>$form ) ) ); 
    }
    else # this eprint has changed since the last reingest
    {
      $page->appendChild( $repo->render_message( "warning", $repo->html_phrase( "arkivum:archive_mismatch", reingest_button=>$form ) ) ); 
    }
  }

  # if we have a list transactions, display those
  if( defined $arkivum_transactions )
  {
    my $ind = 0;
    $arkivum_transactions->map(sub {
      my ($session, undef, $ark_t) = @_;
      $page->appendChild( $self->render_arkivum_transaction( $ark_t, $ind ) );    
      $ind++;
    });
  }

  return $page;
}

sub render_arkivum_transaction
{
  my( $self, $ark_t, $ind ) = @_;

  my $repo = $self->{repository};
  my $eprint = $self->{processor}->{eprint};
  my $ul = $repo->xml->create_element( "ul" ); # wrapper

  my $frag = $repo->make_doc_fragment;
  my $div = $repo->make_element( "div", class => "arkivum_document" );

  my $status_info = $frag->appendChild( $repo->make_element( "div", class=>"ep_arkivum_view_panel" ) );

  my $arkivum_status = $ark_t->stepwise_arkivum_status;
  #  $content->appendChild($ark_t->render_citation("default", arkivum_status=>$arkivum_status));
  $status_info->appendChild($ark_t->render_citation("default", 
    arkivum_status=>$arkivum_status, 
    arkivumid => [$ark_t->id,"STRING"],
    eprint_revision => [$ark_t->value("eprint_revision"),"STRING"],
    timestamp => [$ark_t->value("timestamp"),"STRING"],
    arkivum_actions=>[$self->render_arkivum_actions($eprint, $ark_t, $ind),"XHTML"],
    transaction_index => [$ind,"INTEGER"],
  ));

  return $frag;
}

sub render_eprint_title_summary
{

  my( $self, $ark_t, $eprint, $field ) = @_;

  my $repo = $self->{repository};

  my $frag = $repo->make_doc_fragment;
frag->appendChild(
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

sub render_arkivum_actions
{
  my( $self, $eprint, $ark_t, $is_not_latest ) = @_;

  my $repo = $self->{repository};

  my $arkivum_actions = $repo->make_element( "div", class=> "arkivum_actions" );

  my $arkivum_screen = $self->{session}->plugin( "Screen::ManageArkivum", processor => $self->{processor}, arkivumid => $ark_t->id, eprintid => $eprint->id );

  my $report_button = $self->render_action_button_if_allowed(
    {
      action => "report",
      screen => $arkivum_screen,
      screen_id => $arkivum_screen->{id},
    },
    {
      eprintid => $eprint->id,
      arkivumid => $ark_t->id,
    },
  );

  my $restore_button = $self->render_action_button_if_allowed(
    {
      action => "restore_to_local",
      screen => $arkivum_screen,
      screen_id => $arkivum_screen->{id},
    },
    {
      eprintid => $eprint->id,
      arkivumid => $ark_t->id,
    },
  );

  my $deletion_button = $self->render_action_button_if_allowed(
    {
      action => "request_deletion",
      screen => $arkivum_screen,
      screen_id => $arkivum_screen->{id},
    },
    {
      eprintid => $eprint->id,
      arkivumid => $ark_t->id,
    },
  );

  $arkivum_actions->appendChild( $report_button );
  $arkivum_actions->appendChild( $restore_button );
  $arkivum_actions->appendChild( $deletion_button );

  return $arkivum_actions;
}

sub allow_reingest
{
  my( $self ) = @_;

  my $repo = $self->{repository};

  if( !defined $self->{processor}->{arkivum_transactions} )
  {
    # we have no transactions, but can we create one?
    if( $repo->call( ['arkivum','can_archive_eprint'], $self->{processor}->{eprint} ) )
    {
        return 1;
    }    
  }
  else
  {
    # otherwise we have transactions, so let's check the latest and see if it matches our current fingerprint
    my $latest = $self->{processor}->{arkivum_transactions}->item( 0 );
    return undef if ( !defined $latest );
  
    # does the latest one match the eprint? If so don't allow reingest, but if the eprint has changed, we're good to go ahead
    return $latest->value("archive_fingerprint") ne $latest->take_fingerprint($self->{processor}->{eprint});
  }
}


sub action_reingest
{
  my( $self ) = @_;
  my $repo = $self->{repository};
  return undef if ( !defined $repo );

  my $eprint = $self->{processor}->{eprint};
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
