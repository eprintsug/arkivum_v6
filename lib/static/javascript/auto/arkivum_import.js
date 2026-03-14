var EPrints_Screen_Arkivum_Loader = Class.create({
    has_problems: 0,
    count: 0,
    runs: 0,
    progress: null,
    ids: Array(),
    step: 20,
    prefix: '',
    onProblems: function() {},
    onFinish: function() {},
    url: "",
    parameters: "",
    container: null,

    // to show a pretty progress bar (% compliance):
    total_dataobjs: 0,
    total_noncompliant: 0,

    initialize: function(opts) {
        if( opts.ids )
            this.ids = opts.ids;
        if( opts.step )
            this.step = opts.step;
        if( opts.prefix )
            this.prefix = opts.prefix;
        if( opts.onFinish )
            this.onFinish = opts.onFinish;
        if( opts.onProblems )
            this.onProblems = opts.onProblems;
        if( opts.url )
        {
            this.url = opts.url;
        }
        if( opts.parameters )
            this.parameters = opts.parameters;
        if( opts.container_id )
            this.container = $( opts.container_id );    // should fail if container doesn't exist...
    },

    execute: function() {
        // progress-bar

        this.container.insert( new Element( 'div', { 'class': 'ep_report_progress_bar', 'id': this.prefix + "_progress_bar" } ) );

        var current_grouping = null;    // might not be set in the returned value but that's allowed/OK

        var records = {};
        var seen_ids = {};
        this.no_items = this.ids.length;
        this.retrieved = [];

        for(var i = 0; i < this.ids.length; i+=this.step)
        {
            // arguments for Ajax query AND creates the HTML placeholders <div>'s (that will receive the content of the Ajax query...)
            var args = '&ajax='+this.prefix;
            for(var j = 0; j < this.step && i+j < this.ids.length; j++)
            {
                args += '&' + this.prefix + '=' + this.ids[i+j];
                var id = this.prefix + '_' + this.ids[i+j];
                var target_el = $( id );
                if( target_el != null )
                {
                    //store a record of this in seen_ids to ensure each placeholder has a unique id
                    if( !(id in seen_ids) )
                    {
                        seen_ids[id] = 1;
                    }
                    else
                    {
                        seen_ids[id] = seen_ids[id] + 1;
                    }
                    id = id + "_" + seen_ids[id];
                }

                this.container.insert( new Element( 'div', { 'class': 'ep_report_row', 'id': generateHash(id), 'position': i+j } ), { 'position': 'after' } );
            }

                new Ajax.Request( this.url, {
                                method: 'get',
                    parameters: this.parameters + args,
                onSuccess: (function(transport) {

                                        var json = transport.responseText.evalJSON();
                                        var data = json.data;
                                        if( data == null )
                                                data = new Array();
                                        for( var i=0; i<data.length; i++ )
                                        {
                                                var entry = data[i];
                                                if( entry == null )
                                                        continue;

                                                var path = entry.path;
                                                if( path == null )
                                                        continue;
                                                if( !(path in records) )
                                                {
                                                        this.count++;
                                                        records[path] = entry;
                                                }
                                        }
                                        // we've retrieved all the records
                                        if( this.count == this.no_items )
                                        {
                                                $( this.prefix + '_progress_bar' ).remove();
                                                if( this.has_problems )
                                                        this.onProblems(this);
                                                this.onFinish(this);

                                                //add the eprint summaries
                                                var added_ids = {};
                        for (var key in records)
                                                {
                                                        var entry = records[key];

                                                        //store that we have added this objectid
                                                        if( !(key in added_ids) )
                                                        {
                                                                added_ids[key] = 0;
                                                        }
                                                        else
                                                        {
                                                                added_ids[key] = added_ids[key] + 1;
                                                        }
                                                        this.total_dataobjs++;
                            console.log(entry);
                                                        var name = entry.name;

                                                        var target_id = this.prefix + '_' + key;
                                                        if( added_ids[key] > 0 )
                                                        {
                                                                target_id = target_id + '_' + added_ids[key];
                                                        }
                            target_id = generateHash(target_id);
                                                        var target_el = document.getElementById(target_id);
                                                        if( target_el != null && name != null )
                                                        {
                                if( entry.is_directory == 'true')
                                {
                                                                  var dir_el = target_el.appendChild( new Element( 'div', { 'class': 'ep_arkivum_directory' } ) );
                                  directory_name = name.split('/').at(-1);
                                                                  dir_el.update( directory_name );

                                }else{
                                                                  var filename_el = target_el.appendChild( new Element( 'div', { 'class': 'ep_arkivum_filename' } ) );
                                                                  filename_el.update( name );
                                }

                                                                var details_el = target_el.appendChild( new Element( 'dl', { 'class': 'ep_arkivum_details' } ) );
                                if( entry.is_directory !== 'true' )
                                {
                                  var dt = details_el.appendChild( new Element( 'dt', { 'class': 'ep_arkivum_field' } ) );
                                  dt.update( "Size:" );

                                  var dd = details_el.appendChild( new Element( 'dd', { 'class': 'ep_arkivum_value' } ) );
                                  dd.update( humanFileSize(entry.size, false, 2) );

                                  var dt = details_el.appendChild( new Element( 'dt', { 'class': 'ep_arkivum_field' } ) );
                                  dt.update( "Created:" );

                                  var dd = details_el.appendChild( new Element( 'dd', { 'class': 'ep_arkivum_value' } ) );
                                  dd.update( entry.created );

                                                                  var form = document.createElement("form");
                                                                  form.setAttribute('method',"post");
                                                                  form.setAttribute('action',"/cgi/users/home#t");
                                                                  form.setAttribute('enctype',"multipart/form-data");

                                                                  var screen = document.createElement("input"); //
                                                                  screen.setAttribute('type',"hidden");
                                                                  screen.setAttribute('value',"Admin::ArkivumImport");
                                                                  screen.setAttribute('name',"screen");
                                                                  form.appendChild(screen);

                                                                  var name = document.createElement("input"); // arkivum filename
                                                                  name.setAttribute('type',"hidden");
                                                                  name.setAttribute('value', entry.name);
                                                                  name.setAttribute('name',"name");
                                                                  form.appendChild(name);

                                                                  var path = document.createElement("input"); // arkivum path
                                                                  path.setAttribute('type',"hidden");
                                                                  path.setAttribute('value', entry.path);
                                                                  path.setAttribute('name',"path");
                                                                  form.appendChild(path);

                                                                  var size = document.createElement("input"); // file size
                                                                  size.setAttribute('type',"hidden");
                                                                  size.setAttribute('value', entry.size);
                                                                  size.setAttribute('name',"size");
                                                                  form.appendChild(size);

                                                                  var mime = document.createElement("input"); // file mime type
                                                                  mime.setAttribute('type',"hidden");
                                                                  mime.setAttribute('value', entry.size);
                                                                  mime.setAttribute('name',"mime_type");
                                                                  form.appendChild(size);

                                  var submit = document.createElement("input"); //submit button
                                  submit.setAttribute('class', "btn btn-primary arkivum-import");
                                  submit.setAttribute('type',"submit");
                                  submit.setAttribute('value',"Import Record");
                                  submit.setAttribute('name',"_action_create_eprint");
                                  form.appendChild(submit);

                                  var submit_local = document.createElement("input"); //submit button
                                  submit_local.setAttribute('class', "btn btn-primary arkivum-import-local");
                                  submit_local.setAttribute('type',"submit");
                                  submit_local.setAttribute('value',"Import Record with Local Copy");
                                  submit_local.setAttribute('name',"_action_create_eprint_with_local");
                                  form.appendChild(submit_local);

                                  var remaining = humanFileSize(entry.available - entry.size, false, 2);
                                  var remaining_span = document.createElement("span"); //submit button
                                  remaining_span.setAttribute('class', "remaining");
                                  remaining_span.update( "Space remaining after import: " + remaining );
                                  form.appendChild(remaining_span);
                                                                  target_el.appendChild(form);

                                }else{

                                  var form = document.createElement("form");
                                                                  form.setAttribute('method',"post");
                                                                  form.setAttribute('action',"/cgi/users/home#t");
                                                                  form.setAttribute('enctype',"multipart/form-data");

                                                                  var screen = document.createElement("input"); //
                                                                  screen.setAttribute('type',"hidden");
                                                                  screen.setAttribute('value',"Admin::ArkivumImport");
                                                                  screen.setAttribute('name',"screen");
                                                                  form.appendChild(screen);

                                                                  var name = document.createElement("input"); // arkivum filename
                                                                  name.setAttribute('type',"hidden");
                                                                  name.setAttribute('value', directory_name);
                                                                  name.setAttribute('name',"directory_name");
                                                                  form.appendChild(name);

                                                                  var path = document.createElement("input"); // arkivum path
                                                                  path.setAttribute('type',"hidden");
                                                                  path.setAttribute('value', entry.path);
                                                                  path.setAttribute('name',"path");
                                                                  form.appendChild(path);

                                  var submit = document.createElement("input"); //submit button
                                  submit.setAttribute('class', "btn btn-primary arkivum-import");
                                  submit.setAttribute('type',"submit");
                                  submit.setAttribute('value',"Enter Sub-Directory");
                                  form.appendChild(submit);

                                                                  target_el.appendChild(form);

                                }

                                                                target_el.show();
                                                        }
                                                }
                                        }
                                        else
                                        {
                                                var width = 200;
                                                $( this.prefix + '_progress_bar' ).style.backgroundPosition = Math.round(-width + width * this.count / this.ids.length) + "px 0px";
                                        }

                                        if( this.runs == 0 && this.count == 0 )
                                        {
                                                var pNode = $( this.prefix + '_progress_bar' ).parentNode;
                                                $(this.prefix + '_progress_bar').remove();
                                                var span = new Element( 'span', { 'class': 'ep_ref_report_empty' } );
                                                span.update( 'Report empty' );
                                                pNode.insert( span );
                                        }
                                        this.runs++;

                                }).bind(this)
                        });
                }
                if( this.ids == null || this.ids.length == 0 )
                {
                        var pNode = $(this.prefix + '_progress_bar').parentNode;
                        $(this.prefix + '_progress_bar').hide();
                        var span = new Element( 'span', { 'class': 'ep_ref_report_empty' } );
                        span.update( 'Report empty' );
                        pNode.insert( span );
                }
        }
});

const generateHash = (string) => {
  let hash = 0;
  for (const char of string) {
    hash = (hash << 5) - hash + char.charCodeAt(0);
    hash |= 0; // Constrain to 32bit integer
  }
  return hash;
};

/**
 * Format bytes as human-readable text.
 *
 * @param bytes Number of bytes.
 * @param si True to use metric (SI) units, aka powers of 1000. False to use
 *           binary (IEC), aka powers of 1024.
 * @param dp Number of decimal places to display.
 *
 * @return Formatted string.
 */
function humanFileSize(bytes, si=false, dp=1) {
  const thresh = si ? 1000 : 1024;

  if (Math.abs(bytes) < thresh) {
    return bytes + ' B';
  }

  const units = si
    ? ['kB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB']
    : ['KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB', 'ZiB', 'YiB'];
  let u = -1;
  const r = 10**dp;

  do {
    bytes /= thresh;
    ++u;
  } while (Math.round(Math.abs(bytes) * r) / r >= thresh && u < units.length - 1);


  return bytes.toFixed(dp) + ' ' + units[u];
}
