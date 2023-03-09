=head1 NAME

EPrints::Plugin::Export::Bagit

=cut

package EPrints::Plugin::Export::Bagit;

use File::Copy;
use File::Spec;
use Digest::MD5 qw(md5_hex);

use JSON::PP;
use Data::Dumper;

use Encode;

@ISA = ( "EPrints::Plugin::Export" );
use EPrints::Plugin::Export;

use strict;

sub new
{
    my( $class, %opts ) = @_;

    my $self = $class->SUPER::new( %opts );

    $self->{name} = "Bagit";
    $self->{accept} = [ 'dataobj/eprint', 'list/eprint' ]; 
    $self->{visible} = "all";
    $self->{mimetype} = 'application/gzip';

    return $self;
}

sub output_dataobj
{
    my( $self, $dataobj, %opts ) = @_;
    my $session = $self->{session};

    my $arkivumid = $opts{arkivumid};
    my $eprintid = $dataobj->id;
    my @results = $self->_log("Export", "start $eprintid", 1);

    my $prefix = "";

    if (defined $session->config( 'DPExport', 'transfer_prefix' ) ){
        if ($session->config( 'DPExport', 'transfer_prefix' ) ne "") {
            $prefix = $session->config( 'DPExport', 'transfer_prefix' )."-";
        }
    }

    # get the main, non-volatile documents
    my @docs = $dataobj->get_all_documents;
    my $numDocs = scalar @docs;

    # create directory to store exported files
    my $target_path = $session->config( "arkivum", "path" ) . "/$prefix$eprintid";
    print STDERR "Export Plugin Target Path: $target_path\n";	

    # for metadata only records, export these in a designated folder if set, skip if metadata_only_path not set
    if ($numDocs eq 0){
        push @results, $self->_log("WARNING - No Documents", "Metadata Only Record", 2);
        # if metadata_only_path not set, output warning and skip over and do not export anything out for this one
        if (defined $session->config( "arkivum", "metadata_only_path") && $session->config( "arkivum", "metadata_only_path") ne "" ){
            #export metadata only record into designated folder
            $target_path = $session->config( "arkivum", "metadata_only_path" ) . "/$prefix$eprintid";
        }
        else {
            push @results, $self->_log("metadata_only_path not set", "Skipping", 2);
            return @results;
        }
    }

    my $archive_root = $session->get_repository->get_conf( "archiveroot" );
    my $data_path = "$target_path/data";

    ### objects
    my $rv = $self->_make_dir( $data_path );
    push @results, $self->_log("WARNING - Mkdir", "Directory already exists '$data_path'", 2) if $rv == -1;

    ## documents
    my %hash_cache;	# store checksums to save recalculating them

    foreach my $doc ( @docs )
    {
        my $docid = $doc->id;

        # create a directory for each doc
        my $local_path = $doc->local_path;
        $local_path =~ s#^$archive_root##;
        my $doc_path= $data_path . $local_path;
        $self->_make_dir( $doc_path );

        # and then create a file directory for each file
        foreach my $file ( @{$doc->get_value( "files" )} )
        {
            # and copy the file into the new file dir
            my $filename = $file->get_value( "filename" );
            my $fileid = $file->get_value ("fileid");
            my $filesize = $file->get_value("filesize");
            $filename =~ s/\x27/=0027/g;
            $filename =~ s/\x22/=0022/g;
            $filename =~ s/\x3a/=003a/g;
            my $local_path = $doc->local_path . "/" . $filename;

            my $h = $file->get_value( 'hash' );
            #warn/act on missing hashes in EPrints
            if (! defined ($h)) {
                push @results, $self->_log("WARNING - Checksum MISSING - ", "'$local_path/$filename'", 2);
                if( $session->config( 'DPExport', 'add_missing_checksums' ) ) {# only rehash if enabled
                    push @results, $self->_log("Hashing new MD5 for file ", "'$local_path/$filename'", 2);
                    $file->update_md5;
                    $file->commit;
                    $h = $file->get_value( 'hash' );
                }
                else {
                    push @results, $self->_log("Automatic rehashing disabled, enable with add_missing_checksums in plugin config", "'$local_path/$filename'", 3);
                }
            }
            
            my $ht = $file->get_value( 'hash_type' );

            $hash_cache{ "$local_path/$filename" } = $h if $h && $ht && $ht eq "MD5";
            my $ok = copy($local_path, "$doc_path/$filename"); 
            if (! $ok) {# or warn "Copy failed: $!";
                push @results, $self->_log("Error - COPY failed", "$!", 2);
            } 
            push @results, $self->_log("Copy", "'$local_path' '$doc_path/$filename' (fileid:$fileid docid:$docid hash:$h filesize:$filesize)", $ok);
        }
    }

    ### metadata
    $rv = $self->_make_dir( $data_path );
    push @results, $self->_log("WARNING - Mkdir", "Directory already exists '$data_path'", 2) if $rv == -1;

    ## ep3.xml
    my $xml = $session->xml;
        my $doc = $xml->parse_string( $dataobj->export( "XML" ) );
    push @results, $self->_log("Write", "$data_path/EP3.xml", 1); 
    EPrints::XML::write_xml_file( $doc, "$data_path/EP3.xml" );

    ## revisions 
    # create a directory to copy the revisions to
    if( 0 )
    {
        my $revisions_path = $dataobj->local_path;
        $revisions_path =~ s#^$archive_root##;
        $revisions_path = $data_path . $revisions_path . "/revisions";
        $self->_make_dir( $revisions_path );

        # now copy the actual revisions
        my $eprint_revisions_path = $dataobj->local_path . "/revisions";
        opendir my $eprint_revisions_dir, "$eprint_revisions_path" or warn "Cannot open directory: $!";
        my @revisions = readdir $eprint_revisions_dir;
        foreach my $revision ( @revisions )
        {
            if( $revision =~ /^[\d]+\.xml$/ )
            {
                my $ok = copy("$eprint_revisions_path/$revision", "$revisions_path/$revision"); # or warn "Copy failed: $!";
                push @results, $self->_log("Copy", "'$eprint_revisions_path/$revision' '$revisions_path/$revision'", $ok);
            }
        }
    }

    ## Dublin Core JSON
    # first get the generic DC export plugin and use it to get an array of data
    my $dc_export = $session->plugin( "Export::DC" );
    my $dc_metadata = $dc_export->convert_dataobj( $dataobj );
    #    print Dumper($dc_metadata)."\n";
    #my @headers = map { "dc.".$_->[0] } @{$dc_metadata};
    my @headers;
    foreach my $dc_data (@{$dc_metadata})
    {
            push @headers, "dc.".$dc_data->[0];
    }    
    my @values;
    foreach my $dc_data (@{$dc_metadata})
    {
        #        print STDERR Dumper( $dc_data );
        if( $dc_data->[0] eq "date" )
        {
            my($year,$month,$day) = split /-/, $dc_data->[1];
            push @values, '' unless defined $year;
            $month=1 unless defined $month;
            $day=1 unless defined $day;
            my $date = DateTime->new(year=>$year, month=>$month, day=>$day);
            push @values, $date;
        }
        else
        {
            push @values, $dc_data->[1];
        }
    }
    #    print STDERR Dumper( @values );
    #my @values = map { $_->[1] } @{$dc_metadata};
    # Maybe remove the identifier that is the citation if we can identify it

    use Text::CSV_XS;
    my $dc_file = "ark-file-meta.csv";
    my $dc_file_path = "$target_path/$dc_file";
    my $csv = Text::CSV_XS->new ({ binary => 1, auto_diag => 1, eol => $/ });

    my $identifiers = [{eprintid => $dataobj->id },{arkivumid => $arkivumid}];
    my $i = 0;
    foreach(@{$identifiers}){
        push @headers, ("identifiers.".$i.".identifier", "identifiers.".$i.".identifierType");
        $i++;
    }

    unshift @headers, ("id","type","parent_id");
    open my $fh, ">:encoding(utf8)", $dc_file_path or warn "$dc_file_path: $!";
    $csv->print($fh,\@headers);

    # Collection line
    # push @values, ($dataobj->id, "eprintid");
    foreach my $id (@{$identifiers}){
        while(my($key,$value) = each(%{$id})){
            push @values, ($value, $key);
        }
    }

    unshift @values, ("BagitCollection_".$eprintid."_".$arkivumid,"C","");
    $csv->print($fh,\@values);

    # Object line
    my @object_values = ("BagitObject_".$eprintid."_".$arkivumid,"O","BagitCollection_".$eprintid."_".$arkivumid,"BagitObject_".$eprintid."_".$arkivumid);
    $csv->print($fh,\@object_values);

    # File lines
    # get all the files from the objects directory
    my @file_paths;
    $self->_read_dir( $data_path, \@file_paths );

    foreach my $file_path ( @file_paths ){

        my $relativePath = File::Spec->abs2rel ($file_path,  $target_path."/data");

        my @file_values = ($relativePath,"F","BagitObject_".$eprintid."_".$arkivumid,"");
        print STDERR "Relative_path in export: $relativePath\n";
        next if($relativePath eq $dc_file);
        $csv->print($fh,\@file_values);
    }

    close $fh;


=comment
	#create arrays for the different dc_export values
	if(0){
    my @creator_names;
	my @identifier_names;
	my @title_names;
	my @type_names;
	my @type_rights;
	my @type_language;
	my @type_format;
	my @type_date;
	my @type_relation;
	
	#create a hash to store the new values
	my %dc_hash;
	
	
	#push each value in the exported DC metadata to corresponding arrays
	foreach my $metadata ( @{$dc_metadata} )
        {	
	     my $dc_key = $metadata->[0];
		 my $dc_value = $metadata->[1];
		 
		 if (defined ($dc_value)){
			 if ($dc_key eq "creator")
			 {

				push @creator_names, $dc_value;

			 }
			 elsif ($dc_key eq "identifier")
			 {

				push @identifier_names, $dc_value;

			 }
			 elsif ($dc_key eq "title")
			 {

				push @title_names, $dc_value;

			 }

			elsif ($dc_key eq "type")
			 {

				push @type_names,  $dc_value;

			 }

			 elsif ($dc_key eq "rights")
			 {

				push @type_rights, $dc_value;

			 }

			 elsif ($dc_key eq "language")
			 {

				push @type_language, $dc_value;

			 }

			 elsif ($dc_key eq "format")
			 {

				push @type_format, $dc_value;

			 }

			 elsif ($dc_key eq "date")
			 {

				push @type_date, $dc_value;

			 }

			 elsif ($dc_key eq "relation")
			 {

				push @type_relation, $dc_value;

			 }
		 }
	}
	
	#push arrays to matching hash fields
	if ( @creator_names){
		if ( @creator_names > 1){
			$dc_hash{"dc.creator"} = \@creator_names;
			}
		else {$dc_hash{"dc.creator"} = $creator_names[0];}
	}
	if ( @identifier_names){
		if ( @identifier_names > 1){
			$dc_hash{"dc.identifier"} = \@identifier_names;
			}
		else {$dc_hash{"dc.identifier"} = $identifier_names[0];}
	}
	if ( @title_names){
		if ( @title_names > 1){
			$dc_hash{"dc.title"} = \@title_names;
			}
		else {$dc_hash{"dc.title"} = $title_names[0];}
	}
	if ( @type_rights){
		if ( @type_rights > 1){
			$dc_hash{"dc.rights"} = \@type_rights;
			}
		else {$dc_hash{"dc.rights"} = $type_rights[0];}
	}
	if ( @type_language){
		if ( @type_language > 1){
			$dc_hash{"dc.language"} = \@type_language;
			}
		else {$dc_hash{"dc.language"} = $type_language[0];}
	}
	if ( @type_format){
		if ( @type_format > 1){
			$dc_hash{"dc.format"} = \@type_format;
			}
		else {$dc_hash{"dc.format"} = $type_format[0];}
	}
	if ( @type_date){
		if ( @type_date > 1){
			$dc_hash{"dc.date"} = \@type_date;
			}
		else {$dc_hash{"dc.date"} = $type_date[0];}
	}
	if ( @type_relation){
		if ( @type_relation > 1){
			$dc_hash{"dc.relation"} = \@type_relation;
			}
		else {$dc_hash{"dc.relation"} = $type_relation[0];}
	}
	if ( @type_names){
		if ( @type_names > 1){
            $dc_hash{"dc.type"} = \@type_names;
        }
        else {$dc_hash{"dc.type"} = $type_names[0];}
}


    #create variable for hash
    my $hash_to_json_data = \%dc_hash;

    #convert hash to json
    # my $json_export = $session->plugin( "Export::JSON" );
    my $json = '['.$json_export->output_dataobj( $hash_to_json_data ).']';
    my $json = '['.encode_json( $hash_to_json_data ).']';	

    #add filename (objects/documents folder) as the first key-value pair
    substr($json,0,2) = "[{\"filename\":\"objects/documents\",";	

    #print json to metadata.json file
    my $dc_file_path = "$data_path/ark-manifest.json";
    open(my $fh, '>', $dc_file_path) or warn "Could not open file '$dc_file_path' $!";
    print $fh $json;
    close $fh;
        } #endof if(0)
=cut

    ## Checksum manifest

    # set up the manifest file
    my $manifest_file_path = "$target_path/manifest-md5.txt";
    open(my $manifest_fh, '>', $manifest_file_path) or warn "Could not open file '$manifest_file_path' $!";
    
    # loop through the files in the objects dir and add them to manifest
    foreach my $file_path ( @file_paths )
    {
        open(my $fh, '<', $file_path) or warn "Could not open file '$file_path' $!";
        my $ctx = Digest::MD5->new;
        $ctx->addfile( $fh );
        my $digest = $ctx->hexdigest;
        close $fh;

        # Check if the recorded checksum matches the one just calculated.
        # TODO : For now add an alert in the manifest, later we need to act according to local config
        my $info = ( defined $hash_cache{ $file_path } && $hash_cache{ $file_path } ne $digest ) ? " # !checksum mismatch!" : "";

        my $relativePath = File::Spec->abs2rel ($file_path,  $target_path);

        my $ok = 1;

        if ( !defined( $hash_cache{ $file_path } )) {
            #missing checksum in EPrints - this means something failed since new checksum should have been regenerated by this script 
            $ok = 0;
            push @results, $self->_log("ERROR - checksum MISSING ", "$file_path", $ok);
        }
        elsif ($hash_cache{ $file_path } ne $digest ) {
            #mismatch
            $ok = 0;
            push @results, $self->_log("ERROR - checksum MISMATCH ", "$file_path", $ok);	
        }

        # if( $digest eq "b279ef4488a7d6c12d4e95c5249389f2" ) { $ok = 0 } # fake up a checksum error - justin
        push @results, $self->_log("Manifest", "Checksum correct for '$file_path$info' ($digest)", $ok) if $ok == 1;
        push @results, $self->_log("Manifest", "Checksum error for '$file_path$info' ($digest)", $ok) if $ok == 0;

        print $manifest_fh $digest . "  " . encode( 'utf8', $relativePath ) . $info . "\n";
    }
    close $manifest_fh;

    # the Bagit files
    my $bagit_file_path = "$target_path/bagit.txt";
    open(my $bagit_fh, '>', $bagit_file_path) or warn "Could not open file '$bagit_file_path' $!";
    print $bagit_fh "BagIt-Version: " . $session->config( 'arkivum', 'bagit_version' ) . "\n";
    print $bagit_fh "Tag-File-Character-Encoding: " . $session->config( 'arkivum', 'bagit_encoding' );
    close $bagit_fh;

    push @results, $self->_log("Export", "end $eprintid", 1);

    print STDERR "metadatapath: $dc_file_path\n";
    return ( $target_path, $dc_file_path );

    return @results;
}

sub _log
{
    my( $self, $verb, $text, $ok ) = @_;

    return "[$ok] $verb - $text";
}

sub _make_dir
{
    my( $self, $dir ) = @_;

    if( -d $dir )
    {
        return -1;
    }
    else
    {
        return EPrints::Platform::mkdir( $dir );
    }
}

sub _read_dir
{
    my( $self, $path, $file_paths ) = @_;

    if( -d $path ) # we have a directory
    {
        opendir my $dir, "$path" or warn "Cannot open directory: $!";
        my @contents = readdir $dir;
        closedir $dir;
        foreach my $item ( @contents )
        {
            next if( $item eq "." || $item eq "..");

            $self->_read_dir( "$path/$item", $file_paths );
        }
    }
    elsif( -f $path ) # we have a file
    {
        push @$file_paths, decode( 'utf8', $path );
        return $file_paths;
    }
}

sub _escape_value
{
    my( $self, $value ) = @_;

    return '""' unless( defined EPrints::Utils::is_set( $value ) );

    # strips any kind of double-quotes:
    $value =~ s/\x93|\x94|"/'/g;
    # and control-characters
    $value =~ s/\n|\r|\t//g;

    # if value is a pure number, then add ="$value" so that Excel stops the auto-formatting (it'd turn 123456 into 1.23e+6)
    if( $value =~ /^[0-9\-]+$/ )
    {
        return "\"$value\"";
    }

    # only escapes row with spaces and commas
    if( $value =~ /,| / )
    {
        return "\"$value\"";
    }
    return $value;
}

1;
