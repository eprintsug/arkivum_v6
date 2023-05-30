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

sub properties_from
{
    my( $self ) = @_;

    $self->SUPER::properties_from;

    $self->{processor}->{arkivum_transactions} = EPrints::DataObj::Arkivum->search_by_eprintid( $self->{repository}, $self->{processor}->{eprint}->id );
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

  $page->appendChild( $repo->xml->create_element( "br" ) );

  # header stuff 
  $page->appendChild(my $h2 = $repo->make_element("h2") );
  $h2->appendChild($repo->make_text("Arkivum transactions for "));
  $h2->appendChild($eprint->render_value("title"));

  # headline action 
  if( $self->allow_reingest )
  {
    my $reingest_btn = $self->render_action_button(
        {
            action => "reingest",
            screen => $self,
        }
    );

    $page->appendChild( $repo->render_message( "warning", $repo->html_phrase( "arkivum:archive_mismatch", reingest_button=>$reingest_btn ) ) ); 
  }

  if( $self->{processor}->{arkivum_transactions} )
  {
    my $ind = 0;
    $self->{processor}->{arkivum_transactions}->map(sub {
      my ($session, undef, $ark_t) = @_;
      $page->appendChild( $self->render_arkivum_transaction( $ark_t, $ind ) );    
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

  $eprint = $repo->get_dataset("eprint")->dataobj($ark_t->value("eprintid")) if $ark_t->is_set("eprintid");

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
  $arkivum_actions->appendChild( $self->render_action_list_bar( "arkivum_transaction_actions", {
        eprintid => $eprint->id,
        arkivumid => $ark_t->id,
  } ) ); 

  return $arkivum_actions;
}

sub allow_reingest
{
  my( $self ) = @_;

  my $repo = $self->{repository};
 
  if( !defined $self->{processor}->{arkivum_transactions} )
  {
      # we have no transactions, but can we create one?

  }

  # otherwise we have transactions, so let's check the latest and see if it matches our current fingerprint
  my $latest = $self->{processor}->{arkivum_transactions}->item( 0 );
  return undef if ( !defined $latest );

  return $latest->value("archive_fingerprint") ne $latest->take_fingerprint($self->{processor}->{eprint});
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
