package EPrints::Plugin::Screen::EPrint::ArkivumV6;

our @ISA = ( 'EPrints::Plugin::Screen::EPrint' );

use strict;
use Data::Dumper;

sub new
{
  my( $class, %params ) = @_;
  
  my $self = $class->SUPER::new(%params);

  $self->{actions} = [qw/ report reingest restore request_deletion/];

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

sub render
{
  my( $self ) = @_;

  my $repo = $self->{repository};
  my $page = $repo->xml->create_element( "div" ); # wrapper

  my $eprint = $self->{processor}->{eprint};

  $page->appendChild( $repo->xml->create_element( "br" ) );
 
  my $arkivum_transactions = EPrints::DataObj::Arkivum->search_by_eprintid($repo, $eprint->id );
  print STDERR "LOOK: ".$arkivum_transactions->count."\n";
  $arkivum_transactions->map(sub {
    my ($session, undef, $at) = @_;

    $page->appendChild( $self->render_arkivum_transaction($at) );

  });
 
  return $page;
}

sub render_arkivum_transaction
{
  my( $self, $ark_t ) = @_;

  my $repo = $self->{repository};
  my $eprint = $self->{processor}->{eprint};
  my $ul = $repo->xml->create_element( "ul" ); # wrapper

  my $doc = $repo->get_dataset("document")->dataobj($ark_t->value("docid")) if $ark_t->is_set("docid");
  $eprint = $repo->get_dataset("eprint")->dataobj($ark_t->value("eprintid")) if $ark_t->is_set("eprintid");

  my $frag = $repo->make_doc_fragment;
  my $div = $repo->make_element( "div", class => "arkivum_document" );

  print STDERR "HERE2\n";
  my $status_info = $frag->appendChild( $repo->make_element( "div" ) );
  if(defined $doc){
    $status_info->appendChild( $self->render_report($ark_t,$doc) ); 
  }else{
    $status_info->appendChild( $self->render_eprint_report($ark_t,$eprint) ); 
  }

  return $frag;
}

sub render_eprint_report
{

  my( $self, $ark_t, $eprint ) = @_;

  my $repo = $self->{repository};
  my $field = $repo->get_dataset("arkivum")->get_field("arkivum_status");
  
  my $content = $repo->make_doc_fragment;
  
  #$content->appendChild($self->render_arkivum_actions($ark_t));

  my $arkivum_status = $ark_t->stepwise_arkivum_status;
  #  $content->appendChild($ark_t->render_citation("default", arkivum_status=>$arkivum_status));
  $content->appendChild($ark_t->render_citation("default", 
    arkivum_status=>$arkivum_status, 
    arkivum_actions=>[$self->render_arkivum_actions($ark_t),"XHTML"],
    object_title=>[$eprint->render_value("title"),"XHTML"]
  ));

  #  $content->appendChild(EPrints::DataObj::Arkivum::render_arkivum_status($repo,$field,$ark_t->value("arkivum_status"),undef,undef,$ark_t));
  #  my $actions = $con->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) );

  return $content;
}

sub render_report
{

  my( $self, $ark_t, $doc ) = @_;

  my $repo = $self->{repository};
  my $field = $repo->get_dataset("arkivum")->get_field("arkivum_status");
  print STDERR "HERE\n";  
  my $content = $repo->make_doc_fragment;
  #  $content->appendChild($self->render_arkivum_actions($ark_t));

  my $arkivum_status = $ark_t->stepwise_arkivum_status;
  $content->appendChild($ark_t->render_citation("default", 
    arkivum_status=>$arkivum_status, 
    arkivum_actions=>[$self->render_arkivum_actions($ark_t),"XHTML"],
    object_title=>[$doc->render_value("main"),"XHTML"]
  ));

  #  $content->appendChild(EPrints::DataObj::Arkivum::render_arkivum_status($repo,$field,$ark_t->value("arkivum_status"),undef,undef,$ark_t));
  #  my $actions = $con->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) );

  return $content;
}

=comment
sub render_report {

  my( $self, $ark_t, $doc ) = @_;

  my $repo = $self->{repository};
  my $field = $repo->get_dataset("arkivum")->get_field("arkivum_status");
  

  my $content = $repo->make_doc_fragment;
  $content->appendChild(EPrints::DataObj::Arkivum::render_arkivum_status($repo,$field,$ark_t->value("arkivum_status"),undef,undef,$ark_t));
  #  my $actions = $con->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) );
  $content->appendChild($self->render_arkivum_actions($ark_t));

  my $box = $repo->make_element( "div", style=>"text-align: left" );
  $box->appendChild( EPrints::Box::render(
    id => "arkivum_transaction",
    title => $self->render_title_summary($ark_t,$doc,$field),
    content => $content,
    collapsed => 1,
    session => $repo,
  ) );

  return $box;
}
=cut

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
    my( $self ) = @_;

    return 1;     
}

sub allow_reingest
{
    my( $self ) = @_;

    #TODO makethis true only if it is not already successfully ingested

    return 1;    
}

sub allow_restore
{
    my( $self ) = @_;

    return 1; 
}

sub allow_request_deletion
{
    my( $self ) = @_;

    return 1; 
}


sub render_arkivum_actions
{
  my( $self, $ark_t ) = @_;

  my $repo = $self->{repository};

  my $arkivum_actions = $repo->make_element( "div", class=> "arkivum_actions" );

  my $form = $arkivum_actions->appendChild( $self->render_form( "get" ) );
  $form->appendChild( $repo->render_hidden_field( "class", $ark_t->get_dataset_id ) );
  $form->appendChild( $repo->render_hidden_field( "arkivumid", $ark_t->id ) );

  $form->appendChild( $repo->render_action_buttons(
      _order => [ "report", "reingest", "restore", "request_deletion" ],
      report => $repo->phrase( "Plugin/Screen/EPrint/ArkivumV6/action_report:title" ),
      reingest => $repo->phrase( "Plugin/Screen/EPrint/ArkivumV6/action_reingest:title" ),
      restore => $repo->phrase( "Plugin/Screen/EPrint/ArkivumV6/action_restore:title" ),
      request_deletion => $repo->phrase( "Plugin/Screen/EPrint/ArkivumV6/action_request_deletion:title" )
  ));

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

  return undef if ( !defined $repo );

  # get the dataobj we want to update
  my $class = $repo->param( "class" );
  my $dataset = $repo->dataset( $class );
  my $ark_t = $dataset->dataobj( $repo->param( "arkivumid" ) );
  return undef if ( !defined $ark_t );
  my $monitor_event;
  if($ark_t->is_set("docid")){
    # Then start the monitor event
    $monitor_event = EPrints::DataObj::EventQueue->create_unique( $repo, {
      pluginid => "Event::ArkivumV6",
      action => "ingest_document",
      params => [$ark_t->value("docid"), $ark_t->id],
     });
  }else{
     $monitor_event = EPrints::DataObj::EventQueue->create_unique( $repo, {
      pluginid => "Event::ArkivumV6",
      action => "ingest_eprint",
      params => [$ark_t->value("eprintid"), $ark_t->id],
    });
   }

   if(defined $monitor_event){
    $ark_t->set_value("eventid",$monitor_event->{data}->{eventqueueid});
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
