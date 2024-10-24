package EPrints::Plugin::Storage::ArkivumV6;

use EPrints::Plugin::Storage;
use JSON qw(decode_json);
use LWP::UserAgent;
#use Amazon::S3;
use Net::Amazon::S3::Client;

use File::Find;
use File::Spec::Functions qw(abs2rel);

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

sub ingest_eprint {
  my ($self, $eprint, $ark_t_id) = @_;

  # 1) Generate a hash of document pos's to mimetypes
  my $mime_types = {};
  my @docs = $eprint->get_all_documents;
  foreach my $doc ( @docs )
  {
    my $pos = $doc->value( "pos" );
    foreach my $file ( @{$doc->get_value( "files" )} )
    {
        my $filename = $file->get_value( "filename" );
        $mime_types->{$pos}->{$filename} = $file->value( "mime_type" );
    }
  }

  # 2) Create a bag for this eprint
  my ($bagit_path,$metadata_path) = $eprint->export("Bagit", arkivumid=>$ark_t_id);

  # 3) Post tar file to the bucket
  my $bucket_path = $self->_bucket_put_eprint($bagit_path);
  my $bucket_metadata_path = $bucket_path . "/ark-file-meta.csv";

  # 4) Call the ingest endpoint to start the actual ingest - we can point this at the bag "directory"
  my $url = URI->new('/ingest');
  my $folder_path = $self->_unique_folder_name($eprint, $ark_t_id);

  $url->query_form({ingestPath=>$bucket_path, folderPath=> $folder_path, datapool=>$self->_datapool, metadataPath=>$bucket_metadata_path, ingestCreateCol=>"false" });

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

    my( $self, $eprint, $ark_t_id) = @_;

    return $eprint->id."_".$ark_t_id;
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

### Un-used Function ###
=comment
sub _tar_bag {

  my ($self, $bagit_path ) = @_;

  my $arkivum_path = $self->{session}->get_repository->get_conf( "arkivum", "path" );
  my $bagit_zip_path = $bagit_path.".tar.gz";

  $self->_log("Tarring to tmp dir");
  my $tar = Archive::Tar::Wrapper->new(tmpdir => $arkivum_path);
  find(
    sub {
        return unless -f;  # Add only regular files
        my $file_path = $File::Find::name;
        my $rel_path = abs2rel($file_path, $bagit_path);
        $tar->add($rel_path, $file_path);
    },
    $bagit_path
  );

  # tidy away the bag now we've tar'd it AND put the metadata from it in the bucket
  my $tidy = `rm -rf $bagit_path`;

  $self->_log( "And write to $bagit_zip_path" );
  $self->_log( "And zip it this time!!!" );
  $tar->write( $bagit_zip_path, 1 );
  
  # and tidy away the dir used by Tar::Wrapper to make the tar
  $tar = undef;
 
  # Move the compressed bagit file to a cool sounding filename
  use File::Copy;
  my $bagit_cool_name = substr($bagit_path,0,-4);
  print STDERR "Move: $bagit_zip_path --> $bagit_cool_name\n";
  move($bagit_zip_path, $bagit_cool_name);

  return $bagit_cool_name;
}
=cut

sub _bucket_put_eprint {

  my ($self, $bagit_path, $mime_types) = @_;

  # first derive a "cool" name (i.e. strip _BAG off the end...)
  my $bagit_cool_name = substr($bagit_path,0,-4);

  # get our bucket
  my $bucket = $self->_get_ingest_bucket;

  # create a prefix for our bucket keys
  my $arkivum_path = $self->{session}->get_repository->get_conf( "arkivum", "path" );
  my $bucket_key_path = $bagit_cool_name;
  $bucket_key_path =~ s#^$arkivum_path##;

  # now add each file from the Bag to the bucket
  find(
    sub {
        return unless -f;  # Add only regular files
        my $file_path = $File::Find::name;

        # get file size to work out if multi-part upload
        my $file_size = -s $file_path;
        my $rel_path = abs2rel($file_path, $bagit_path);

        # get a key for this file
        my $ingest_path = $self->param( "datapool" ).$bucket_key_path."/".$rel_path;

        # get the mime type
        my $mime = "application/octet-stream";
        if( $rel_path eq "ark-file-meta.csv" )
        {
          $mime = "text/csv";
        }
        elsif( $rel_path eq "data/metadata/EP3.xml" )
        {
          $mime = "text/xml";
        }
        elsif( $rel_path eq "manifest-md5.txt" || $rel_path eq "bagit.txt" )
        {
          $mime = "text/plain";
        }
        elsif( $rel_path =~ m/^data\/documents\/([\d+])\/(.+)$/ )
        {
          my $pos = $0;
          my $filename = $1;
          if( exists $mime_types->{$pos} && exists $mime_types->{$pos}->{$filename} )
          {
            $mime = $mime_types->{$pos}->{$filename};
          }
        }

        # create a bucket object for our file
        my $object = $bucket->object(key=>$ingest_path, content_type=>$mime);

        # do we need to send this as a multiparter?
        my $chunk_threshold = 1 * 1024 * 1024 * 1024; # 1GB
        my $response;
        if( $file_size <= $chunk_threshold ) # this is simple, just put the file as is
        {
          $response = $object->put_filename($file_path);
        }
        else
        {
          # Initiate the multipart upload
          my $upload_id = $object->initiate_multipart_upload;

          # Read the file in chunks and upload each part
          my $part_size = 1 * 1024 * 1024 * 1024; # 1GB
          my @etags;
          my @part_numbers;

          open(my $fh, '<', $file_path) or die "Failed to open file: $!";
          my $part_number = 1;

          while( my $data = _read_chunk( $fh, $part_size, $part_number ) )
          {
            my $put_part_response = $object->put_part(
              upload_id    => $upload_id,
              part_number  => $part_number,
              value    => $data,
            );
            push @etags, $put_part_response->header('ETag');
            push @part_numbers, $part_number;

            $part_number++;
          }

          $response = $object->complete_multipart_upload(
            upload_id => $upload_id,
            etags => \@etags,
            part_numbers => \@part_numbers,
          );
        }
  
        return $self->_handle_bucket_error($response) if $self->{s3_client}->{s3}->err;
    },
    $bagit_path
  );

  # tidy away the bag now we've put in the bucket
  my $tidy = `rm -rf $bagit_path`;

  return $self->param( "datapool" ).$bucket_key_path;
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

sub _bucket_delete_request {

  my ($self, $bucket_key) = @_;

  my $bucket = $self->_get_ingest_bucket;

  my $object = $bucket->object(key=>$bucket_key);

  if ($object->exists) { 
    print STDERR "Removing object from bucket: ".$object->uri."\n";
    $object->delete;
  }

}

sub _log
{
    my ( $self, $msg) = @_;

    $self->{repository}->log($msg);
}

# Helper function to read a chunk from the file
sub _read_chunk {
    my ($fh, $size, $part_number) = @_;
    my $offset = ($part_number - 1) * $size;
    seek($fh, $offset, 0);
    read($fh, my $data, $size);
    return $data;
}

