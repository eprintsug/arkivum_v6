use EPrints::DataObj::Arkivum;

########################################
# ARKIVUM ACCESS
########################################
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{api_host} = "API Host URL";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{datapool} = "Datapool ID";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{token_url} = "Arkivum Token URL";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{client_id} = "Client ID";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{client_secret} = "Client Secret";

$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{bucket_host} = "Bucket Host URL";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{bucket_access_key} = "Bucket Key";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{bucket_access_secret} = "Bucket Secret";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{bucket_region} = "Bucket Region";
$c->{plugins}->{"Storage::ArkivumV6"}->{params}->{bucket_name} = "Bucket Name";

$c->{plugins}{"Event::ArkivumV6"}{params}{disable} = 0;
$c->{plugins}{"Storage::ArkivumV6"}{params}{disable} = 0;
$c->{plugins}{"Screen::ArkivumV6"}{params}{disable} = 0;
$c->{plugins}{"Export::Bagit"}{params}{disable} = 0;

$c->{arkivum}->{bagit_version} = '1.0';
$c->{arkivum}->{bagit_encoding} = 'UTF-8';
$c->{arkivum}->{path} = '/var/tmp/arkivum/test';

push @{$c->{user_roles}{admin}}, qw(
    +arkivum/details
    +arkivum/view
    +eprint/arkivum
);

# Arkivum dataset
$c->{datasets}->{arkivum} = {
    class => "EPrints::DataObj::Arkivum",
    sqlname => "arkivum",
};
 
########## Criteria for archiving #############
# For each relevant dataset (eprint, docuemnt, dile), 
# add metadata fields and lists of values, if any of 
# these values are found in all of the listed metadata 
# fields then we will archive. If a dataset points to 
# an empty hashref then all items in that dataset will 
# match. So if all datasets point to empty hashes we 
# are saying that _everything_ gets archived
$c->{arkivum}->{criteria} = {
    eprint => {
        eprint_status => ['archive'],
        type => ['data_collection']
    },
    document => {},
    file => {}
};

$c->{arkivum}->{significant_metadata} = {
    eprint => ['title']
};
# CACHING 
$c->{arkivum}->{processes} = [qw/
    METADATA_PROCESSING 
    METADATA_EXTRACTION 
    INDEXING 
    INTEGRITY_CHECK 
    VIRUS_SCAN 
    ENCRYPTION 
    REPLICATION 
    FIXITY/];

###############################################

# Check metadata against cretiera
$c->{arkivum}->{can_archive_document} = sub{
    my( $document ) = @_;

    my $eprint = $document->get_parent if $c->{arkivum}->{criteria}->{eprint};
    # We are caring not about files other than main (for criteria at least)
    my $file = $document->stored_file( $document->get_main ) if $c->{arkivum}->{criteria}->{file};
    my $can_archive=1;
    while( my($obj_name,$fields) = each(%{$c->{arkivum}->{criteria}})){
      die("Bad config: $obj_name found in \$c->{arkivum}->{criteria}, should be one of eprint, document or file.") unless( grep {$_ eq $obj_name} @{['eprint','document','file']}); #be fussy pre-eval
      next if !%{$fields}; 
      my $object = eval("\$$obj_name");
      while( my($field,$value) = each(%{$fields})){
        $can_archive=0 unless(grep {$_ eq $object->value($field)} @{$value});
      }
    }
    return $can_archive;
};

# Check metadata against cretiera
$c->{arkivum}->{can_archive_eprint} = sub{
    my( $eprint ) = @_;

    my $can_archive=1;

    while( my($obj_name,$fields) = each(%{$c->{arkivum}->{criteria}})){
      if($c->{arkivum}->{criteria}->{document}){
        for my $document ($eprint->get_all_documents){
        # We are caring not about files other than main (for criteria at least)
          my $file = $document->stored_file( $document->get_main ) if $c->{arkivum}->{criteria}->{file};
        }
        die("Bad config: $obj_name found in \$c->{arkivum}->{criteria}, should be one of eprint, document or file.") unless( grep {$_ eq $obj_name} @{['eprint','document','file']}); #be fussy pre-eval
        next if !%{$fields}; 
        my $object = eval("\$$obj_name");
	
        while( my($field,$value) = each(%{$fields})){
          $can_archive=0 unless(grep {$_ eq $object->value($field)} @{$value});
        }
      }
    }

    return $can_archive;
};

$c->{arkivum}->{create_archive_event} = sub{

  my ( $eprint ) = @_;

  my $repository = $eprint->repository;

  if($repository->call(['arkivum','can_archive_eprint'],$eprint) && $repository->call(['arkivum','should_archive_eprint'],$eprint)){
            
    print STDERR "##### We can and we should!\n";
    my $arkivum_transaction = $repository->dataset( "arkivum" )->create_dataobj(
      {
        eprintid => $eprint->id,
        userid => $repository->current_user->id,
        arkivum_status => '{"message": "archive_scheduled"}',
    }); 

    # The arkivum dataobject will take and store a fingerprint from the eprint
    $arkivum_transaction->set_value("archive_fingerprint",$arkivum_transaction->take_fingerprint($eprint));
    $arkivum_transaction->set_value("eprint_revision",$eprint->get_value("rev_number"));
    $arkivum_transaction->set_value("timestamp",EPrints::Time::get_iso_timestamp);

    my $ingest_event = EPrints::DataObj::EventQueue->create_unique( $repository, {
        pluginid => "Event::ArkivumV6",
        action => "ingest_eprint",
        params => [$eprint->id, $arkivum_transaction->id],
    });

    # before we loose it lets record the event id in the arivum_transaction
    $arkivum_transaction->set_value("eventid",$ingest_event->{data}->{eventqueueid});
    $arkivum_transaction->commit;
  }  
};

$c->{arkivum}->{should_archive_eprint} = sub {

  my ( $eprint ) = @_;

  my $repo = $eprint->repository;

  print STDERR "###### Checking if we should....\n";

  my $arkivum_transaction = EPrints::DataObj::Arkivum->latest_by_eprintid($repo, $eprint->id);
  return 1 if(! defined $arkivum_transaction);

  print STDERR "###### There is an ark transaction already... has it changed in a significant manner\n";

  #  my $current_fingerprint = $repository->call(['arkivum','take_fingerprint'], $eprint);
  my $current_fingerprint = EPrints::DataObj::Arkivum->take_fingerprint($eprint);

  #  my $fingerprint_on_record = $arkivum_transaction->value("archive_fingerprint");
  my $fingerprint_on_record = $arkivum_transaction->value("archive_fingerprint");

  print STDERR "###### Fingerprint on record: $fingerprint_on_record\n";
  print STDERR "###### fingerprint of suspect: $current_fingerprint\n";

  return $fingerprint_on_record ne $current_fingerprint;

};

$c->add_dataset_trigger( "eprint", EP_TRIGGER_STATUS_CHANGE , 
  sub 
  {
    my ( %params ) = @_;
    my $repository = $params{repository};

    return undef if (!defined $repository);

    if (defined $params{dataobj}){
      my $eprint = $params{dataobj};
      #      my $eprintid = $dataobj->id;
      # Get the eprint object so we can check the status
      #my $eprint = new EPrints::DataObj::EPrint( $repository, $eprintid );
      $repository->call(['arkivum','create_archive_event'],$eprint) if ( defined $eprint ); 
    }

  }
);
	
