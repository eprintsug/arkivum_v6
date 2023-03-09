package EPrints::Plugin::Storage::ArkivumV6;

use EPrints::Plugin::Storage;
use JSON qw(decode_json);
use LWP::UserAgent;
#use Amazon::S3;
use Net::Amazon::S3::Client;

use LWP::Authen::OAuth2;
use Data::Dumper;

@ISA = ("EPrints::Plugin::Storage");

use strict;

sub new {
  my($class, %params) = @_;

  my $self = $class->SUPER::new( %params );

  $self->{name} = "Arkivum v6 Storage";

  # See lib/lang/en/phrases/system.xml for storage classes
  $self->{storage_class} = "x_cloud_archival_storage";
  $self->{arkivum} = undef; # The authenticated arkivum api connection

  return $self;
}

sub ingest_document {
  my ($self,$doc) = @_;

  # First step is to put the file into the ingest bucket (as specified in config)
  my $ingest_path = $self->_bucket_put_doc($doc);
  my $metadata_path = $self->_bucket_put_metadata($doc->parent);

  print STDERR "HAVE INGEST PATH: $ingest_path\n";
  print STDERR "HAVE METADATA PATH: $metadata_path\n";
  # Get the metadata path. If we are ingesting a document we will need to get the associated metadata for that doc
  # probably that will be the doc-<parnet->dc_xml
  # my $metadata_path = $self->_get_metadata_path($doc);


  # Then we call the ingest endpoint to start the actual ingest
  my $url = URI->new('/ingest');
  my $folder_path = $self->_documents_path."/".$doc->parent->value('dir');

  print STDERR "HAVE FOLDER PATH: $folder_path\n";

  #  $url->query_form({ingestPath=>$ingest_path, folderPath=> $folder_path, datapool=>$self->param("datapool"), metadataPath=>$metadata_path});
  $url->query_form({ingestPath=>$ingest_path, datapool=>$self->param("datapool"), metadataPath=>$metadata_path});


  return $self->_arkivum_post_request($url, undef);
}

sub ingest_eprint {
  my ($self,$eprint) = @_;

  # First step is to put the file into the ingest bucket (as specified in config)
  my ($bucket_path,$metadata_path) = $self->_bucket_put_eprint($eprint);
  my $bucket_metadata_path = $self->_bucket_put_metadata($metadata_path);

  print STDERR "HAVE BUCKET PATH: $bucket_path\n";
  print STDERR "HAVE METADATA PATH: $bucket_metadata_path\n";

  # Then we call the ingest endpoint to start the actual ingest
  my $url = URI->new('/ingest');
  #  my $folder_path = $self->_datapool."/".$eprint->value('dir');
  my $folder_path = $self->_datapool."/".$self->_unique_folder_name($eprint);

  print STDERR "HAVE FOLDER PATH: $folder_path\n";

  #  $url->query_form({ingestPath=>$bucket_path, folderPath=> $folder_path, datapool=>$self->param("datapool"), metadataPath=>$metadata_path, isArchive=>"true" });
  $url->query_form({ingestPath=>$bucket_path, folderPath=> $folder_path, datapool=>$self->_datapool, isArchive=>"true", metadataPath=>$bucket_metadata_path });

  return $self->_arkivum_post_request($url, undef);
}

sub monitor {
  my ($self, $transaction_to_monitor, $transaction_id) = @_;
  
  use Switch;

  switch ($transaction_to_monitor) {
    case /^ingest/       { return $self->_monitor_ingest($transaction_id); }
    case /^export/       { return $self->_monitor_export($transaction_id); }
    case /^preservation/ { return $self->_monitor_preservation($transaction_id); } 
    else                 { $self->_log("Transaction to monitor not found: $transaction_to_monitor"); return undef; }
  }
  
}
sub _monitor_ingest {
  my ($self, $ingest_id) = @_;

  return $self->_arkivum_get_request("/ingest/$ingest_id/report", undef);
 
}
# Delete the local copy and request deletion of Arkivum copy
# Based on Storage::Local::delete with insert for Arkivum API calls
sub delete {

  return 1;
}



################## Arkivum util methods ###################


sub _arkivum_get_ingest_report
{
        my( $self ) = @_;

}


sub _is_arkivum_file_local
{
}

# replicates the old get_fileInfo but fileInfo does not tell us much
sub _arkivum_get_file_info
{
}

# An as yet untested delete_file (if works will make a deltion request to arkivum api)
# need to find out how to get the token for this request
sub _arkivum_delete_file
{
        my( $self, $filename) = @_;

        # What is the token? It is probably not hte filename anymore
        my $token = ""; # something more like this maybe? 6367a2fe7d038255d5f2430d
        my $endpoint = "/ops/aggregation/" . $token;

        my $response = $self->_arkivum_delete_request($endpoint);

        $response  = $self->_handle_response($response);

        return $response;

}

################################
# OAuth for arkivum api requests
################################
sub _connect {
  my ($self) = @_;

  if(!defined$self->{arkivum}  || ($self->{arkivum}->can_refresh && $self->{arkivum}->should_refresh)){
    $self->{arkivum} = $self->_authenticate;
  }
  return $self->{arkivum};
}

sub _authenticate {
  my ($self) = @_;
 
  my $client_id = $self->param( "client_id" );
  # Constructor
  my $oauth2 = LWP::Authen::OAuth2->new(
    client_id => $client_id,
    client_secret => $self->param( "client_secret" ),
    token_endpoint => $self->param( "token_url" ),

    # Optional hook, but recommended.
    #    save_tokens => \&self->_save_tokens,
    #    save_tokens_args => [ $dbh ],
 
    # This is for when you have tokens from last time.
    #token_string => $token_string,
  );

  $oauth2->request_tokens(code => "unused_pretend_code", grant_type => "client_credentials");
  return $oauth2;
}
sub _save_tokens {
  my ($token_string) = @_;
  
  print STDERR "TOKEN STRING: ".$token_string."\n";
}
##########################################
# Util methods for arkivum api interaction
##########################################

# Do some consistent generic response handling if all is well, 
# pass decoded and json parsed content back to the caller for 
# further processing
sub _handle_response {
        my( $self, $response) = @_;

        if ( not defined $response ) {
                $self->_log("Invalid response returned");
                return;
        }
        if ($response->is_error){
            $self->_log("Error response: ".Dumper($response));
            return decode_json($response->decoded_content);
        }

        return decode_json($response->decoded_content);
}

# Clean endpoints and build api request uri 
# based on config host and datapool(s)
sub _build_request_uri {

    my( $self, $endpoint, $file_ref ) = @_;

    my $api_host = $self->param( "api_host" );
    print STDERR "API HOST: ".$api_host."\n";
    $endpoint =~ s/^\///; #strip leading slash from enpoint
    $file_ref =~ s/^\/// if $file_ref; #strip leading slash from file_ref
    $api_host =~ s/\/$//; #strip trailing slash from api_host
    my $req_uri = $api_host .'/'. $endpoint;
    $req_uri .= $self->param( "datapool" ).'/'.$file_ref if $file_ref;
    return $req_uri;
}

# returns a version of the file path that can be used 
# to store the file in an easily addressable location 
# in arkivum
sub _file_path_to_arkivum_path {

    my( $self, $file_path) = @_;

    # Get the root path for repository as it would be on local storage
    my $archive_root = $self->{session}->get_repository->get_conf( "archiveroot" );
   
    # Get the configured mount path for the Arkivum storage and append the repo id to it
    my $datapool = $self->param( "datapool" );

    $file_path =~ s#$archive_root#$datapool#;

    return $file_path;
}

sub _datapool {

    my( $self) = @_;

    return $self->param( "datapool" );
}

sub _unique_folder_name {

    my( $self, $eprint) = @_;

    return $eprint->id."_".EPrints::DataObj::Arkivum->latest_by_eprintid($eprint->{session},$eprint->id)->id;
}

sub _documents_path {

    my( $self) = @_;

    # Get the root path for repository as it would be on local storage
    my $archive_root = $self->{session}->get_repository->get_conf( "archiveroot" );
   
    # Get the configured mount path for the Arkivum storage and append the repo id to it
    my $documents_path = $self->{session}->get_repository->get_conf( "documents_path" );

    $documents_path =~ s#^$archive_root##;

    return $documents_path;
}


sub _arkivum_get_request
{
    my( $self, $endpoint, $file_ref ) = @_;

    my $arkivum = $self->_connect; # returns an LWP::Authen::OAuth2 thingimy-jig
    my $response = $arkivum->get( $self->_build_request_uri($endpoint, $file_ref), 'Content_Type' => 'application/json' );

    return $self->_handle_response($response);
}

sub _arkivum_post_request
{
    my( $self, $endpoint, $file_ref, $data ) = @_;

    my $arkivum = $self->_connect; # returns an LWP::Authen::OAuth2 thingimy-jig
    my $response = $arkivum->post( $self->_build_request_uri($endpoint, $file_ref), 'Content_Type' => 'application/json' );

    return $self->_handle_response($response);
}

sub _arkivum_delete_request
{
    my( $self, $endpoint, $file_ref ) = @_;

    my $ua = LWP::UserAgent->new();
    my $req = HTTP::Request->new(DELETE => $self->_build_request_uri($endpoint, $file_ref));
    my $response = $ua->request($req);

    return $self->_handle_response($response);
}

##############################
# Bucket work
# - connect
# - put file (aka key)
#
sub _bucket_connect {
    my ($self) = @_;

    return Net::Amazon::S3::Client->new({
        aws_access_key_id     => $self->param("bucket_access_key"),
        aws_secret_access_key => $self->param("bucket_access_secret"),
        retry                 => 1,
  });

}

sub _handle_bucket_error {
  my ($self, $response) = @_;

  $self->_log("####### BUCKET ERROR: " . $response );
  return;

}

sub _get_ingest_bucket {

  my ($self) =@_;
  my $client = $self->_bucket_connect;
  $self->{s3_client} = $client;

  return $self->_handle_bucket_error($client) if ! $client;

  my $bucket = $client->bucket( name => $self->param("bucket_name") );
  #my $bucket = $s3->bucket($self->param("bucket_name"),region=>$self->param("bucket_region")); 
  return $self->_handle_bucket_error($bucket) if $client->{s3}->err;

  return $bucket;
   
}

sub _bucket_put_doc {

  my ($self, $doc) = @_;

  my $bucket = $self->_get_ingest_bucket;

  # TODO this will only get one file per document !!
  my $file_obj = $doc->stored_file( $doc->get_main );
  my $file_path = $file_obj->get_local_copy();
  # Deal with EPrints vagueness
  if(ref($file_path) eq "File::Temp"){
    $file_path = $file_path->filename;
  }
  # Turn the local file path into an address we can use in bucket (and beyond)
  my $ingest_path=$self->_file_path_to_arkivum_path($file_path);
  
  my $response = $bucket->add_key_filename($ingest_path,$file_path,{content_type=>$file_obj->value('mime_type')});
  return $self->_handle_bucket_error($response) if $self->{s3_client}->{s3}->err;
  return $ingest_path;

}

sub _bucket_put_eprint {

  my ($self, $eprint) = @_;

  my $bucket = $self->_get_ingest_bucket;

  my ($bagit_path,$metadata_path) = $eprint->export("Bagit", arkivumid=>EPrints::DataObj::Arkivum->latest_by_eprintid($eprint->{session},$eprint->id)->id);
  # TODO replcae this with a perl library as long as it works just like this stuff 
  my $bagit_zip_path = $bagit_path.".tar.gz";
  my $bucket_key_path = $bagit_zip_path;
  my $arkivum_path = $self->{session}->get_repository->get_conf( "arkivum", "path" );
  $bucket_key_path =~ s#^$arkivum_path##;

  # This exec will leave a . (dot) in the path
  #my $output = `/bin/tar -zcf $bagit_zip_path -C $bagit_path *`;
  # This one will not insert a . (dot)
  my $output = `find $bagit_path -printf "%P\n" -type f -o -type l -o -type d | tar -czf $bagit_zip_path --no-recursion -C $bagit_path -T -`;

  # Turn the local file path into an address we can use in bucket (and beyond)
  # my $ingest_path=$self->_file_path_to_arkivum_path($bagit_path);
  #my $ingest_path=EPrints::Utils::uri_escape_utf8($self->param( "datapool" )).$bucket_key_path;
  my $ingest_path=$self->param( "datapool" ).$bucket_key_path;
  #  my $response = $bucket->add_key_filename($ingest_path,$bagit_zip_path,{content_type=>'application/gzip'});
  my $object = $bucket->object(key=>$ingest_path, content_type=>'application/gzip');
  my $response = $object->put_filename($bagit_zip_path);
  return $self->_handle_bucket_error($response) if $self->{s3_client}->{s3}->err;
  return ($ingest_path,$metadata_path);
}

# POssibibly unused if we use bags
sub _bucket_put_metadata {

  my ($self, $metadata_path) = @_;

  my $bucket = $self->_get_ingest_bucket;

  my $bucket_metadata_path = $metadata_path;
  my $arkivum_path = $self->{session}->get_repository->get_conf( "arkivum", "path" );
  $bucket_metadata_path =~ s#^$arkivum_path##;

  # Turn the local file path into an address we can use in bucket (and beyond)
  my $ingest_path=$self->param( "datapool" ).$bucket_metadata_path;
   
  my $object = $bucket->object(key=>$ingest_path,content_type=>'text/xml');
  my $response = $object->put_filename($metadata_path);

  return $self->_handle_bucket_error($response) if $self->{s3_client}->{s3}->err;
  return $ingest_path;
}

sub _bucket_get_request {

}

sub _log
{
    my ( $self, $msg) = @_;

    $self->{repository}->log($msg);
}

