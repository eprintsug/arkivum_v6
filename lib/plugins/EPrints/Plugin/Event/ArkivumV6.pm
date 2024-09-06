package EPrints::Plugin::Event::ArkivumV6;

@ISA = qw( EPrints::Plugin::Event );

use strict;

use JSON qw(decode_json encode_json);
use Data::Dumper;

sub new
{
    my( $class, %params ) = @_;

    my $self = $class->SUPER::new( %params );

    $self->{actions} = [qw( enable disable )];
    $self->{disable} = 0; # always enabled, even in lib/plugins

    $self->{package_name} = "ArkivumV6";
    $self->{timeout} = 3600;

    # Enable debug logging
    $self->_set_debug(1);

    return $self;
}

sub ingest_eprint {
  my( $self, $eprintid, $ark_t_id) = @_;

  print STDERR "### In ingest_eprint_as_bagit\n";
  # Get the repository
  my $repository = $self->{repository};
  # Check the document we need to copy
  my $eprint = new EPrints::DataObj::EPrint( $repository, $eprintid );
  if ( not defined $eprint )
  {
    $self->_log("Document: $eprintid not found");
    return EPrints::Const::HTTP_NOT_FOUND;
  }

  # Get the specific ArkivumStorage plugin
  my $arkivum_storage = $repository->plugin( "Storage::ArkivumV6" );
  if ( not defined $arkivum_storage )
  {
    $self->_log("Could not get the Arkivum plugin for Document ".$eprint->id."...");
    return EPrints::Const::HTTP_NOT_FOUND;
  }

  #Get arkivum transaction dataobj and set the event_id
  #  my $ark_t = EPrints::DataObj::Arkivum( $repository, $ark_t_id );
  my $ark_t = $repository->get_dataset("arkivum")->get_object( $repository, $ark_t_id );
  my $ingest_response = $arkivum_storage->ingest_eprint($eprint, $ark_t_id);

  if(!defined($ingest_response) || !$ingest_response){
    $ark_t->set_value("arkivum_status", '{"local_message":"error"}');
    $ark_t->commit;
    return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
  }
  
  print STDERR "##### ".Dumper($ingest_response)."\n";
  # If we are here then we should have had a successful _start_ of an ingest
  # update the status of the arkivum_transaction and record the ingest_id
  if(! defined $ingest_response->{ingestId}){
      $ark_t->set_value("arkivum_status", encode_json($ingest_response));
      $ark_t->commit;
      return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;

  }else{
    $ark_t->set_value("ingestid", $ingest_response->{ingestId});
    $ark_t->set_value("arkivum_status", '{"local_message":"ingest_started"}');
    $ark_t->commit;
  }


  # Then start the monitor event
  my $monitor_event = EPrints::DataObj::EventQueue->create_unique( $repository, {
    pluginid => "Event::ArkivumV6",
    action => "ingest_report",
    params => [$ingest_response->{ingestId}, $ark_t_id],
  });
 
  # before we loose it lets record the event id in the arivum_transaction
  $ark_t->set_value("eventid",$monitor_event->{data}->{eventqueueid});
  $ark_t->commit;

  # and complete this event
  return EPrints::Const::HTTP_OK;
}

sub ingest_report {
  my( $self, $ingestid, $ark_t_id) = @_;
  print STDERR "### In ingest_report\n";
  # Get the repository
  my $repository = $self->{repository};

  # Get the ArkivumStorage plugin
  my $arkivum_storage = $repository->plugin( "Storage::ArkivumV6" );
  if ( not defined $arkivum_storage )
  {
    $self->_log("Could not get the Arkivum plugin ...");
    return EPrints::Const::HTTP_NOT_FOUND;
  }

  # Get arkivum transaction dataobj and set the event_id
  #  my $ark_t = EPrints::DataObj::Arkivum($repository, $ark_t_id);
  my $ark_t = $repository->get_dataset("arkivum")->get_object( $repository, $ark_t_id );

  my $monitor_response = $arkivum_storage->monitor("ingest", $ingestid);

  if(!defined($monitor_response) || !$monitor_response){
    $ark_t->set_value("arkivum_status", "{local_message: 'error'}");
    $ark_t->commit;
    return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
  }
  # We will put the whole report in the DB as json. lazy or genius... as yet undecided
  $ark_t->set_value("arkivum_status", encode_json($monitor_response));
  $ark_t->commit;

  my $success = 0;
  if( defined $monitor_response->{resultList} ){
    #We will quickly run through and estabish whether the steps have all suceeded or if we should remonitor
    print STDERR "###### Checking if there is a resultList.... ".scalar @{$monitor_response->{resultList}};
    $success=1 if scalar @{$monitor_response->{resultList}};
    for my $aggregation(@{$monitor_response->{resultList}}){
      for my $p_step(@{$aggregation->{processingSteps}}){
        $success = 0 if $p_step->{status} ne "SUCCESS";
      }
      for my $p_step(@{$aggregation->{contentEntityProcessingState}->{processingSteps}}){
        $success = 0 if $p_step->{status} ne "SUCCESS";
      }
      while(my($location,$p_steps) = each(%{$aggregation->{contentEntityProcessingState}->{locationProcessingSteps}})){
        for my $p_step (@{$p_steps}){
          $success = 0 if $p_step->{status} ne "SUCCESS";
        }
      }
    }
  }

  my $monitor_attempts = $ark_t->value("monitor_attempts") || 1;
  my $event = $self->_get_event($ark_t);

  print STDERR "### success is $success and monitor_attempts is $monitor_attempts\n";
  if(!$success){
    if($monitor_attempts <= 17){ # 17 attempts == 2^17 = ~36 hours # TODO make that 17 a configurable item
      # We will set the time as per the _get_start_time
      $event->set_value("start_time", $self->_get_start_time($event,$monitor_attempts));
      # Change status to waiting
      $event->set_value( "status", "waiting" );
      # We will keep the event so that it gets picked up again at the start time
      $event->set_value( "cleanup", "FALSE" ); 
      $event->commit;
      # UPdate the monitor_attempt in the arkivum_transaction
      $ark_t->set_value("monitor_attempts",$monitor_attempts+1);
      $ark_t->commit;
      # Send OK
      return EPrints::Const::HTTP_RESET_CONTENT;
    }else{
      # give up and call it a fail...?
      # when we fail reset the monitor attempts in case someone wants to try a reingest
      $ark_t->set_value("monitor_attempts",0);
      $ark_t->commit;
      return EPrints::Const::HTTP_INTERNAL_SERVER_ERROR;
    }
  }
  # Actual success so remove the event on OK
  $event->set_value( "cleanup", "TRUE" );
  $event->commit;

  # Now we are satisfied that there is a successful ingest of this eprint we will make a "copy" of all the files in the docs' file objects have an Arkivum v6 copy
  $self->_make_copy($ark_t);
  $self->_remove_bucket_copy($ark_t);

  return EPrints::Const::HTTP_OK;

}

sub _remove_bucket_copy {

  my ($self, $ark_t) = @_;

  my $repo = $self->{repository};
  my $storage = $repo->plugin("Storage::ArkivumV6");
  
  return undef if ! defined $storage;

  my @bucket_keys;

  my $bucket_key = $storage->param("datapool")."/".$ark_t->value("eprintid")."_".$ark_t->id;
  my $bucket_md_key = $bucket_key."_BAG/ark-file-meta.csv";

  # get keys for everything in the bucket
  my $eprint = $repo->dataset("eprint")->dataobj($ark_t->value("eprintid"));
  my @docs = $eprint->get_all_documents;
  foreach my $doc ( @docs )
  {
    my $pos = $doc->value( "pos" );
    foreach my $file ( @{$doc->get_value( "files" )} )
    {
        my $filename = $file->get_value( "filename" );
        push @bucket_keys, $bucket_key . "/data/documents/" . $pos . "/" . $filename;
    }
  }

  # Expected BagIt files
  push @bucket_keys, $bucket_key . "/bagit.txt";
  push @bucket_keys, $bucket_key . "/data/metadata/EP3.xml";
  push @bucket_keys, $bucket_key . "/manifest-md5.txt";
  push @bucket_keys, $bucket_key . "/ark-file-meta.csv";

  # and now remove each one from the bucket
  foreach my $bk ( @bucket_keys )
  {
    $storage->_bucket_delete_request($bk);
  }
  $storage->_bucket_delete_request($bucket_md_key);

}

sub _make_copy {

  my ($self, $ark_t) = @_;

  my $repo = $self->{repository};
  my $storage = $repo->plugin("Storage::ArkivumV6");
  
  return undef if ! defined $storage;

  my $eprint = $repo->dataset("eprint")->dataobj($ark_t->value("eprintid"));

  foreach my $doc ($eprint->get_all_documents){

	  # Copy all files attached to the document
	  foreach my $file (@{$doc->get_value( "files" )})
	  {
		    # Get/construct URI for this file so we can find it within the Arkivum API
		    my $uri = $self->_get_arkivum_uri($doc, $file, $ark_t->id, $storage->param("api_host"), $storage->param("datapool"));

		    # Create a file->copy with the Storage::ArkivunV6 pluginid now we know that this file is safely in Arkivum
        $file->add_plugin_copy( $storage, $uri );
        $file->commit();
	  }
  }
}

sub _get_arkivum_uri {

  my ($self, $doc, $file, $ark_t_id, $arkivum_host, $datapool) = @_;

  my $arkivum_uri = $arkivum_host."/a6/files/".$datapool."/".$doc->value("eprintid")."_".$ark_t_id."/documents/".$doc->value("pos")."/".$file->value("filename");

  return $arkivum_uri;

}

sub _get_event {
  my ($self, $ark_t) = @_;

  return $self->get_repository->get_dataset("event_queue")->search(
                filters => [
                        { meta_fields => [ 'eventqueueid' ], value => $ark_t->value("eventid"), match => 'EX' },
                ])->item( 0 );
}

sub _get_start_time {

  my ($self,$event,$monitor_attempts) = @_;
  print STDERR "### Monitoring attempts: $monitor_attempts\n";
  my $start_time = EPrints::Time::datetime_utc(EPrints::Time::split_value( $event->value("start_time") )) || time();
  print STDERR "### start time: $start_time\n"; 
  $start_time += 2 ** $monitor_attempts * 60; # try again in an ever increasing number of minutes
  print STDERR "### start time after: $start_time\n"; 

  return EPrints::Time::iso_datetime( $start_time )
}

sub _log
{
    my ( $self, $msg) = @_;
    $self->{repository}->log($msg);
}

sub _set_debug
{
    my ( $self, $enabled) = @_;

    my $repo = $self->{repository};
    if ( $enabled )
    {
        $repo->{noise} = 1;
    }
    else
    {
        $repo->{noise} = 0;
    }
}
