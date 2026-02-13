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
    my $uri = "a6/files/".$self->{session}->param( "path" );
    my $storage = $repo->plugin("Storage::ArkivumV6");

    # create the new eprint
    my $epdata = {
        eprint_status => "inbox",
        userid => $self->repository->current_user->id,
    };
    $epdata->{title} = "Arkivum Import";

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

    my $uri = "a6/files/".$self->{session}->param( "path" );
    my $storage = $repo->plugin("Storage::ArkivumV6");
    my ( $filename, $filepath ) = $storage->_arkivum_get_download($uri, undef);

    # create the new eprint
    my $epdata = {
        eprint_status => "inbox",
        userid => $self->repository->current_user->id,
    };
    $epdata->{title} = "Arkivum Import with Local";

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

sub ajax_arkivum
{
    my( $self ) = @_;

    my $repo = $self->repository;

    my $json = { data => [] };

    my @paths = $repo->param( "arkivum" );
    my $storage = $repo->plugin("Storage::ArkivumV6");
    
    foreach my $path ( @paths )
    {
        my $file_info = $storage->_arkivum_get_request("a6/api/2/files/fileInfo/$path", undef);
        push @{$json->{data}}, {
            path => $file_info->{path},
            name => $file_info->{name},
            created => $file_info->{createdDate},
            size => $file_info->{size},
            available => $self->{available} * 1024,
        };
    }

    print $self->to_json( $json );
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

    # first get the Arkivum data
    my $storage = $repo->plugin("Storage::ArkivumV6");
    my $datapool = $storage->param("datapool_path");
    my $files = $storage->_arkivum_get_request("a6/files/$datapool", undef);

    my %arkivum_files = ();
    foreach my $file ( @{$files->{fileProperties}} )
    {
        next if $file->{directory} == 1;
        $arkivum_files{$file->{path}} = $file->{lastModified};
    }
    
	my @sorted_files;
    foreach my $file (sort { $arkivum_files{$b} cmp $arkivum_files{$a} } keys %arkivum_files )
    {
		push @sorted_files, $file;
    }
	my $json = encode_json \@sorted_files;

	my $container_id = "arkivum_import";
	$frag->appendChild( $repo->make_element( 'div', id => $container_id ) );

	my $url = $repo->current_url( host => 1 );
    my $parameters = URI->new;
    $parameters->query_form(
        $self->hidden_bits,
    );
    $parameters = $parameters->query;



    my $prefix = "arkivum";

    $frag->appendChild( $repo->make_javascript( <<"EOJ" ) );
document.observe("dom:loaded", function() {
    new EPrints_Screen_Arkivum_Loader( {
        ids: $json,
        step: 1,
        prefix: '$prefix',
        url: '$url',
        parameters: '$parameters',
        container_id: '$container_id',
    } ).execute();
});
EOJ

	return $frag
}

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
