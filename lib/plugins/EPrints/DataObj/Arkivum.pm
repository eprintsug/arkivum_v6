package EPrints::DataObj::Arkivum;

our @ISA = qw( EPrints::DataObj::SubObject );

use JSON qw(decode_json encode_json);

use strict;
use Data::Dumper;

# The new method can simply return the constructor of the super class (Dataset)
sub new
{
    return shift->SUPER::new( @_ );
}

sub get_system_field_info
{
    my( $class ) = @_;

    return
    (
        { name=>"arkivumid", type=>"counter", required=>1, import=>0, show_in_html=>0, can_clone=>0, sql_counter=>"arkivumid" },
        { name=>"docid", type=>"itemref", datasetid=>"document", required=>1, show_in_html=>0 },
        { name=>"eprintid", type=>"itemref", datasetid=>"eprint", required=>1, show_in_html=>0 },
        { name=>"userid", type=>"itemref", datasetid=>'user', required=>1, },
        { name => "hash", type => "multipart",
            fields => [
                { sub_name => "filename", type => "id", },
                { sub_name => "hash", type => "id", },
            ],
            multiple => 1,
        },
        { name=>"access_date", type=>"time", required=>0, },
        { name => "arkivum_status", type => 'longtext',	render_value=>"EPrints::DataObj::Arkivum::render_arkivum_status_summary" },
        # can't use item ref because that expectes an int and eventqueueid is a hash
        { name => "eventid", type => "id" },
        { name => "ingestid", type => "id" },
        { name => "monitor_attempts", type => "int" },
    );
}

# This method is required to just return the dataset_id.
sub get_dataset_id
{
    my ($self) = @_;
    return "arkivum";
}

sub parent
{
    my( $self ) = @_;

    my $docid = $self->value('docid');
    return if !$docid;

    return $self->{session}->dataset('document')->dataobj($docid);
}

sub search_by_docid
{
    my( $class, $session, $docid ) = @_;

    return $session->dataset( $class->get_dataset_id )->search(
        filters => [{
            meta_fields => [qw( docid )],
            value => $docid,
            match => "EX",
        }],
    );
}
sub search_by_eprintid
{
    my( $class, $session, $eprintid ) = @_;

    return $session->dataset( $class->get_dataset_id )->search(
        filters => [{
            meta_fields => [qw( eprintid )],
            value => $eprintid,
            match => "EX",
        }],
    );
}

sub latest_by_eprintid
{
    my( $class, $session, $eprintid ) = @_;

    return $session->dataset( $class->get_dataset_id )->search(
        filters => [{
            meta_fields => [qw( eprintid )],
            value => $eprintid,
            match => "EX",
        }],
        order => "-arkivumid",
    )->item(0);
}

sub parse_arkivum_status
{
    my( $self, $arkivum_status ) = @_;
   
    $arkivum_status = $self->value("arkivum_status") if ! defined $arkivum_status;
    return decode_json($arkivum_status);
}

sub stepwise_arkivum_status {

    my( $self ) = @_;

    my $report = $self->parse_arkivum_status;
    my $stepwise_arkivum_status = {};
    if(defined $report->{resultList}){
        for my $aggregation(@{$report->{resultList}}){
            for my $p_step(@{$aggregation->{processingSteps}}){
                $stepwise_arkivum_status->{$p_step->{name}} = [] unless defined $stepwise_arkivum_status->{$p_step->{name}};
                push @{$stepwise_arkivum_status->{$p_step->{name}}} , { aggregationType=>$aggregation->{aggregationType}, 
                    relativePath=>$aggregation->{relativePath},
                    status=>$p_step->{status}, 
                    name=>$p_step->{name},
                    id=>$aggregation->{id},
                };
            }

            for my $p_step(@{$aggregation->{contentEntityProcessingState}->{processingSteps}}){
                $stepwise_arkivum_status->{$p_step->{name}} = [] unless defined $stepwise_arkivum_status->{$p_step->{name}};
                push @{$stepwise_arkivum_status->{$p_step->{name}}} , { aggregationType=>$aggregation->{aggregationType}, 
                    relativePath=>$aggregation->{relativePath},
                    status=>$p_step->{status}, 
                    name=>$p_step->{name},
                    id=>$aggregation->{id},
                };
            }

            while(my($location,$p_steps) = each(%{$aggregation->{contentEntityProcessingState}->{locationProcessingSteps}})){
                for my $p_step (@{$p_steps}){
                    $p_step->{name} = "REPLICATION" if($p_step->{name} eq "REPLICATION_COPY");
                    $stepwise_arkivum_status->{$p_step->{name}} = [] unless defined $stepwise_arkivum_status->{$p_step->{name}};
                    push @{$stepwise_arkivum_status->{$p_step->{name}}} , { aggregationType=>$aggregation->{aggregationType},
                        relativePath=>$aggregation->{relativePath},
                        status=>$p_step->{status}, 
                        location=>$location,
                        name=>$p_step->{name},
                        id=>$aggregation->{id},
                    };
                }
            }
        }
    }else{
        $stepwise_arkivum_status = $report;
    }
    return $stepwise_arkivum_status;
}

sub render_arkivum_status 
{

  my( $repo, $field, $value, $alllangs, $nolink, $ark_t ) = @_;

  my $report = $ark_t->parse_arkivum_status($value);

  my $frag = $repo->make_doc_fragment;
  if(defined $report->{resultList}){

    my $table = $repo->make_element( "div", class => "ep_table arkivum_report" );

    my $header = $table->appendChild( $repo->make_element( "div", class => "ep_table_head ep_table_row" ) );
    my $headings = ["Aggregation", "File", "Location", "Processing Step", "Status"];
    for my $heading (@{$headings}){
      $header->appendChild( 
        $repo->make_element( "div", class => "ep_table_head ep_table_cell" ) )->appendChild(
        $repo->make_text($heading));
    }

    for my $aggregation(@{$report->{resultList}}){
      for my $p_step(@{$aggregation->{processingSteps}}){
        $table->appendChild( $ark_t->render_report_row($repo,$aggregation->{aggregationType},$aggregation->{relativePath},"N/A",$p_step) );
      }
      for my $p_step(@{$aggregation->{contentEntityProcessingState}->{processingSteps}}){
        $table->appendChild( $ark_t->render_report_row($repo,$aggregation->{aggregationType},$aggregation->{relativePath},"N/A",$p_step) );
      }
      while(my($location,$p_steps) = each(%{$aggregation->{contentEntityProcessingState}->{locationProcessingSteps}})){
        for my $p_step (@{$p_steps}){
          $table->appendChild( $ark_t->render_report_row($repo,$aggregation->{aggregationType},$aggregation->{relativePath},$location,$p_step) );
        }
      }
    }
    $frag->appendChild($table);
  }
  if(defined $report->{"errorMessage"}){
    my $div = $repo->make_element("div");
    $div->appendChild($repo->make_text($report->{"errorMessage"}));
    $frag->appendChild($div);
  }

  return $frag;
}

sub render_report_row
{
  my($self,$repo,$aggregation_type,$relative_path,$location,$p_step) = @_;

  my $row = $repo->make_element( "div", class => "ep_table_row" );
  $row->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) )->appendChild(
    $repo->html_phrase("arkivum_aggregation_".$aggregation_type));
  $row->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) )->appendChild(
    $repo->make_text($relative_path));
  $row->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) )->appendChild(
    $repo->make_text($location));
  $row->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) )->appendChild(
    $repo->make_text($p_step->{name}));
  $row->appendChild( $repo->make_element( "div", class => "ep_table_cell" ) )->appendChild(
    $repo->make_text($p_step->{status}));

  return $row;
}

sub render_arkivum_status_summary
{
    my( $repo, $field, $value, $alllangs, $nolink, $ark_t ) = @_;

    my $report = $ark_t->parse_arkivum_status($value);

    my $count = {SUCCESS => 0, PENDING => 0, FAILED => 0, PROCESSING =>, REQUESTED => 0};
    my $total = 0;
    my $div = $repo->make_element( "div", class => "led_panel" );

    if(defined $report->{resultList}){
        for my $aggregation(@{$report->{resultList}}){
 
            for my $p_step(@{$aggregation->{processingSteps}}){
                $count->{$p_step->{status}}++;
                $div->appendChild($repo->make_element( "div", class => "led led_".$p_step->{status}));
                $total++;
            }
    
            for my $p_step(@{$aggregation->{contentEntityProcessingState}->{processingSteps}}){
                $count->{$p_step->{status}}++;
                $div->appendChild($repo->make_element( "div", class => "led led_".$p_step->{status}));
                $total++;
            }
    
            while(my($location,$p_steps) = each(%{$aggregation->{contentEntityProcessingState}->{locationProcessingSteps}})){
                for my $p_step (@{$p_steps}){
                    $count->{$p_step->{status}}++;
                    $div->appendChild($repo->make_element( "div", class => "led led_".$p_step->{status}));
                    $total++;
                }
            }
        }
    
        # Proportional if useful...?
        #my $success = $count->{'SUCCESS'}/$total if $count->{'SUCCESS'} > 0;
        #my $pending = $count->{'PENDING'}/$total if $count->{'PENDING'} > 0;
        #my $failed = $count->{'FAILED'}/$total if $count->{'FAILED'} > 0;
    }
  
    if(defined $report->{"errorMessage"}){
        $div->appendChild($repo->make_element( "div", class => "led led_FAILED"));
    }

    return $div;
}
