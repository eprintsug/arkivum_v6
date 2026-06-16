package EPrints::Plugin::Screen::Admin::ArkivumImport;

use JSON qw(encode_json);

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

use Data::Dumper;

sub new
{
    my( $class, %params ) = @_;

    my $self = $class->SUPER::new(%params);

    $self->{actions} = [qw/ export create_eprint create_eprint_with_local /];

    $self->{appears} = [
        {
            place => "admin_actions_system",
            position => 1265,
        },
    ];

    my( $available, $available_gb ) = $self->_get_diskspace;
    $self->{available} = $available;
    $self->{available_gb} = $available_gb;

    return $self;
}

sub can_be_viewed
{
    my( $self ) = @_;

    my $user = $self->repository->current_user;

    return 0 if !defined $user;

    return 0 if !$user->has_role( 'admin' );

    return 1;

}

sub redirect_to_me_url { }

sub allow_create_eprint { shift->can_be_viewed }
sub action_create_eprint{

    my( $self ) = @_;

    my $repo = $self->repository;

    # download the file? (do we add a separate action that allows for a document to be created
    # but using the arkivum storage plugin to keep it offsite? Yes quite probably!
    my $uri = "a6/files".$self->{session}->param( "path" );
    my $storage = $repo->plugin("Storage::ArkivumV6");
    my $response = $self->get_arkivum_file_metadata( $storage, $self->{session}->param( "path" ) );
    print STDERR Dumper($response)."\n";
    # create the new eprint
    my $epdata = {
        eprint_status => "inbox",
        userid => $self->repository->current_user->id,
    };
    $epdata->{title} = "Arkivum Import";

    if( $repo->config( "arkivum", "use_recollect_workflow" ) )
    {
        $epdata->{type} = 'data_collection';
    }

    my $dataset = $self->{session}->dataset("eprint");
    my $eprint;
    $eprint = $dataset->create_dataobj( $epdata );

    return if !defined $eprint;

    my $filename = $self->{session}->param( "name" );

    # now add the file to the eprint
    my $doc = $eprint->create_subdataobj( "documents", {
        main => $filename,
        format => "other",
    });

    my $file = $doc->create_subdataobj( "files", {
        filename => $filename,
        filesize => $self->{session}->param( "size" ),
    });

    # Create a file->copy with the Storage::ArkivunV6 pluginid now we have our local EPrints version
    $file->add_plugin_copy( $storage, $uri );
    $file->commit();

    # redirect to edit screen....
    $self->{processor}->{dataobj} = $self->{processor}->{eprint} = $eprint;
    $self->{processor}->{dataobj_id} = $self->{processor}->{eprintid} = $eprint->get_id;

    $self->{processor}->{screenid} = "EPrint::Edit";
}

sub allow_create_eprint_with_local { shift->can_be_viewed }
sub action_create_eprint_with_local{

    my( $self ) = @_;

    my $repo = $self->repository;

    my $uri = "a6/files".$self->{session}->param( "path" );
    my $storage = $repo->plugin("Storage::ArkivumV6");
    my ( $filename, $filepath ) = $storage->_arkivum_get_download($uri, undef);

    # create the new eprint
    my $epdata = {
        eprint_status => "inbox",
        userid => $self->repository->current_user->id,
    };
    $epdata->{title} = "Arkivum Import with Local";

    if( $repo->config( "arkivum", "use_recollect_workflow" ) )
    {
        $epdata->{type} = 'data_collection';
    }

    my $dataset = $self->{session}->dataset("eprint");
    my $eprint;
    $eprint = $dataset->create_dataobj( $epdata );

    return if !defined $eprint;

    # now add the file to the eprint
    my $doc = $eprint->create_subdataobj( "documents", {
        main => $filename,
        format => "other",
    });
    my $file = $doc->add_file( $filepath, $filename );


    # Create a file->copy with the Storage::ArkivunV6 pluginid now we have our local EPrints version
    $file->add_plugin_copy( $storage, $uri );
    $file->commit();

    # redirect to edit screen....
    $self->{processor}->{dataobj} = $self->{processor}->{eprint} = $eprint;
    $self->{processor}->{dataobj_id} = $self->{processor}->{eprintid} = $eprint->get_id;

    $self->{processor}->{screenid} = "EPrint::Edit";
}

sub get_arkivum_file_metadata {

  my( $self, $storage, $file_path ) = @_;

  my $dp_path = $storage->param("datapool_path");

  $file_path =~ s#^/$dp_path##g;

  my $query = {
    "types" => ["F"],
    "datapools" => [ $storage->param("datapool")],
    "fileClasses" => ["REGULAR"],
    "queryStringQuery" => "$file_path", #This will currently return lots of vaguely correct results when we want one
    "page"=> 1,
    "pageSize"=> 1,
    #  "content"=> "string",
  };

  return $storage->_arkivum_post_request("es/metadata/search/string/query", undef, $self->to_json( $query ) );

}

sub allow_export { shift->can_be_viewed }
sub action_export {}

sub wishes_to_export {
    $_[0]->repository->param( 'export' ) ||
    $_[0]->repository->param( 'ajax' );
}

sub export_mimetype
{
    my( $self ) = @_;

    if( $self->repository->param( "ajax" ) )
    {
        return "application/json; charset=utf-8";
    }

    return "text/html; charset=utf-8";
}

sub export
{
    my( $self ) = @_;

    my $part = $self->repository->param( "ajax" );
    my $f = "ajax_$part";

    if( $self->can( $f ) )
    {
        binmode(STDOUT, ":utf8");
        return $self->$f;
    }

        return $self->SUPER::export
}

sub ajax_arkivum_file
{
    my( $self ) = @_;

    my $repo = $self->repository;
    print STDERR "ajax_arkivum_file\n";

    my $json = {};

    my $path = $repo->param( "path" );

    #    my @paths = $repo->param( "arkivum" );
    my $storage = $repo->plugin("Storage::ArkivumV6");

    #foreach my $path ( @paths )
    #{
        my $file_info = $storage->_arkivum_get_request("a6/api/2/files/fileInfo/$path", undef);
        $json = {
            type => "file",
            path => $file_info->{path},
            name => $file_info->{name},
            created => $file_info->{createdDate},
            size => $file_info->{size},
            available => $self->{available} * 1024,
        };
        #}

    print $self->to_json( $json );
}

# ajax call to get the contents of our starting directory/any sub directories
sub ajax_arkivum_dir
{
    my( $self ) = @_;

    my $repo = $self->repository;
    print STDERR "ajax_arkivum_dir\n";

    # first get the Arkivum data
    my $storage = $repo->plugin("Storage::ArkivumV6");
    print STDERR "we have storage....$storage\n";
    my $datapool = $storage->param("datapool_path");
    my $dir = $repo->param( "path" );
    print STDERR "get request for dir....$dir\n";
    my $files = $storage->_arkivum_get_request($dir, undef);
    print STDERR "files....".Dumper($files)."\n";
    my %arkivum_files = ();
    foreach my $file ( @{$files->{fileProperties}} )
    {
       $arkivum_files{$file->{path}}{lastModified} = $file->{lastModified};
       $arkivum_files{$file->{path}}{size} = $file->{size};
       $arkivum_files{$file->{path}}{md5sum} = $file->{md5};
       $arkivum_files{$file->{path}}{path} = $file->{path};
       if( $file->{directory} )
       {
           $arkivum_files{$file->{path}}{type} = "dir";
       }
       else
       {
           $arkivum_files{$file->{path}}{type} = "file";
       }
    }

    my @sorted_files;
    foreach my $file (sort { $arkivum_files{$b}{lastModified} cmp $arkivum_files{$a}{lastModified} } keys %arkivum_files )
    {
        push @sorted_files, $arkivum_files{$file};
    }

    print $self->to_json( \@sorted_files );
}


sub render
{
    my( $self ) = @_;

    my $repo = $self->{repository};
    my $xml = $repo->xml;
    my $xhtml = $repo->xhtml;

    # first display how much space is available
    my $frag = $xml->create_document_fragment;

    $frag->appendChild( my $available_div = $repo->make_element( 'div', class => "arkivum_available" ) );
    $available_div->appendChild( $self->html_phrase( "arkivum_available", available => $repo->make_text( $self->{available_gb} ) ) );

=comment
    if( $self->{session}->param("directory_name") )
    {
      $frag->appendChild( my $in_dir_div = $repo->make_element( 'div', class => "arkivum_available" ) );
      $in_dir_div->appendChild( $self->html_phrase( "arkivum_in_dir", dir => $repo->make_text( $self->{session}->param("directory_name" ) ) ) );
      $frag->appendChild( my $back_link = $repo->make_element( 'p' ) );
      $back_link->appendChild( $self->html_phrase( "arkivum_back_to_root" ) );
    }
=cut

    # set up a space where we're going to display our tree of Arkivum contents
    my $container_id = "arkivum_import";
    $frag->appendChild( my $wrap = $repo->make_element( 'div', class => "tree-wrap" ) );
    $wrap->appendChild( my $toolbar = $repo->make_element( 'div', class => "toolbar" ) );
    $toolbar->appendChild( my $button = $repo->make_element( 'button', onclick => "expandAll()" ) );
    $toolbar->appendChild( my $button = $repo->make_element( 'button', onclick => "collapseAll()" ) );

    $wrap->appendChild( $repo->make_element( 'div', id => $container_id ) );

=comment

  <div class="tree-wrap">
    <div class="toolbar">
      <button onclick="expandAll()">Expand all</button>
      <button onclick="collapseAll()">Collapse all</button>
      <div class="toggle-wrap">
        <label for="icon-toggle">Material icons</label>
        <input type="checkbox" id="icon-toggle" checked onchange="setIconMode(this.checked)" />
      </div>
    </div>
    <div id="tree-root"></div>
  </div>

=cut

    # build our initial query parth, probably direct-upoad
        my $storage = $repo->plugin("Storage::ArkivumV6");
    my $datapool = $storage->param("datapool_path");
    my $import_sub_path = $repo->config("arkivum", "import_sub_path");
    my $files_endpoint = "$datapool/$import_sub_path";
    if($self->{session}->param("path"))
    {
        my $path = $self->{session}->param("path");
        $files_endpoint = "$path";
    }

    my $url = $repo->current_url( host => 1 );
    my $parameters = URI->new;
    $parameters->query_form(
        $self->hidden_bits,
    );
    $parameters = $parameters->query;

    # set  up the Ajax Arkivum loader
    #    $frag->appendChild( $repo->make_javascript( <<"EOJ" ) );
    #document.observe("dom:loaded", function() {
    #var data = new EPrints_Screen_Arkivum_Loader( {
    #    path: '$files_endpoint',
    #    url: '$url',
    #    parameters: '$parameters',
    #    container_id: '$container_id',
    #} ).get_arkivum_dir();
    #console.log(data);
    #});
    #EOJ
    $frag->appendChild( $repo->make_javascript( <<"EOJ" ) );
document.observe("dom:loaded", function() {
    var data = new EPrints_Screen_Arkivum_Loader( {
        path: '$files_endpoint',
        url: '$url',
        parameters: '$parameters',
        container_id: '$container_id',
    } );
});
EOJ

        return $frag
}

=comment
not here... in the javascript
sub load_arkivum_directory_data
{
    my( $self ) = @_;

    my $repo = $self->{repository};

    # first get the Arkivum data
    my $storage = $repo->plugin("Storage::ArkivumV6");
    my $datapool = $storage->param("datapool_path");
    my $import_sub_path = $repo->config("arkivum", "import_sub_path");
    my $files_endpoint = "a6/files/$datapool/$import_sub_path";
    if($self->{session}->param("path"))
    {
        my $path = $self->{session}->param("path");
        $files_endpoint = "a6/files$path";
    }
    my $files = $storage->_arkivum_get_request($files_endpoint, undef);

}
=cut

sub to_json
{
        my( $self, $object ) = @_;

    return "" if( !defined $object );

        # UTF-8 issues:
        #   return JSON->new->utf8(1)->encode( $object );

    if( ref( $object ) eq 'HASH' )
        {
                my @stuff;
                while( my( $k, $v ) = each( %$object ) )
                {
                        next if( !EPrints::Utils::is_set( $v ) );       # or 'null' ?
                        push @stuff, EPrints::Utils::js_string( $k ).':'.$self->to_json( $v )
                }
                return '{' . join( ",", @stuff ) . '}';
        }
        elsif( ref( $object ) eq 'ARRAY' )
        {
                my @stuff;
                foreach( @$object )
                {
                        next if( !EPrints::Utils::is_set( $_ ) );
                        push @stuff, $self->to_json( $_ );
                }
                return '[' . join( ",", @stuff ) . ']';
        }

        return EPrints::Utils::js_string( $object );
}

sub _get_diskspace
{
    my( $self ) = @_;

    my $repo = $self->repository;
    my $app_mount_point = $repo->config( "arkivum", "app_mount" );
    my $app_output = `df -k '$app_mount_point'`;

    if( $app_output eq "" )
    {
        return 0;
    }
    else
    {
        my @lines = split /\n/, $app_output;
        shift @lines; # skip header line

        my ($filesystem, $size, $used, $available, $use, $mount) = split /\s+/, $lines[0];

        # Convert KB to GB
        my $allocated_gb = sprintf("%.2f", $size / 1024 / 1024) . "GB";
        my $used_gb   = sprintf("%.2f", $used   / 1024 / 1024) . "GB";
        my $available_gb = sprintf("%.2f", $available / 1024 / 1024) . "GB";

        return( $available, $available_gb );
    }

}
