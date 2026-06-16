var EPrints_Screen_Arkivum_Loader = Class.create({
    url: "",
    parameters: "",
    container: null,
    path: '',
    hierarchy: {}, // this is where we build up our hierarchy ready to display later

    initialize: function(opts) {

        if( opts.path )
            this.path = opts.path;
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

        this.total_size = 0;
        self=this;
        this.buildFileStructure(`a6/files/${this.path}`).then(function(result) {
            arkivum_dir = [{path: `/${opts.path}`, type: 'dir', children: result}];
            tree = renderAll(arkivum_dir);
            console.log("TOTAL_SIZE: ",self.total_size);
        });
    },

    buildFileStructure: async function (path) {
      const contents = await this.fetchDirectory(path);

      const entries = await Promise.all(
        contents.map(async (entry) => {
          console.log(entry);
          if (entry.type === 'dir') {
            return {
              path: entry.path,
              type: 'dir',
              children: await this.buildFileStructure(`a6/files${entry.path}`)
            };
          }
          this.total_size += +entry.size;
          return { path: entry.path, size: entry.size, md5sum: entry.md5sum, type: 'file' };
        })
      );

      return entries;
    },
    fetchDirectory: async function (path) {
      args = "ajax=arkivum_dir&path="+path;

      const response = await fetch(`${this.url}?${this.parameters}&${args}`);

      return response.json();
    },

    get_arkivum_file: (item)=> {
        args = "&ajax=arkivum_file&path="+item.path;

        new Ajax.Request( this.url, {
            method: 'get',
            parameters: this.parameters + args,
            onSuccess: (function(transport) {
                var json = transport.responseText.evalJSON();
                this.file_tree_json.push(json);
            }),
            onFailure: (function(transport) {console.log("failed"); console.log(transport);}),
        });
    },

    get_arkivum_dir: function(path) {
        console.log("get_arkivuM_dir");
 //       if(item !== undefined){
   //       args = "&ajax=arkivum_dir&path=a6/files"+path;
  //      }else{
          args = "&ajax=arkivum_dir&path="+path;
  //      }

        console.log("ARGS: ",args);
        //var self = this;
        new Ajax.Request( this.url, {
            method: 'get',
            parameters: this.parameters + args,
            onSuccess: (function(transport) {
                var json = transport.responseText.evalJSON();
                console.log(json);
                for(var i = 0; i < json.length; i++)
                {
                    var item = json[i];
                    if( item.type === "dir" )
                    {
                        //this.path = item.path;
                        this.file_tree_json.push(item);
                        this.get_arkivum_dir(item.path);
                    }
                    else // we have a file
                    {
                        console.log("get file:", item);
                        this.get_arkivum_file(item);
                    }
                }

            })
        });
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

// -------------------------------------------------------
// Icon maps
// -------------------------------------------------------
var EMOJI_ICONS = {
  pdf:'📄', js:'📜', jsx:'📜', ts:'📜', tsx:'📜',
  css:'🎨', html:'🌐', md:'📝', json:'📋',
  ico:'🖼', png:'🖼', jpg:'🖼', svg:'🖼', txt:'📄'
};

var MATERIAL_FILE = {
  pdf:  { glyph:'picture_as_pdf', cls:'pdf'   },
  jpg:  { glyph:'image',          cls:'image' },
  jpeg: { glyph:'image',          cls:'image' },
  png:  { glyph:'image',          cls:'image' },
  gif:  { glyph:'image',          cls:'image' },
  svg:  { glyph:'image',          cls:'image' },
  ico:  { glyph:'image',          cls:'image' },
  js:   { glyph:'code',           cls:'code'  },
  jsx:  { glyph:'code',           cls:'code'  },
  ts:   { glyph:'code',           cls:'code'  },
  tsx:  { glyph:'code',           cls:'code'  },
  html: { glyph:'code',           cls:'code'  },
  css:  { glyph:'code',           cls:'code'  },
  md:   { glyph:'description',    cls:'text'  },
  txt:  { glyph:'description',    cls:'text'  },
  json: { glyph:'data_object',    cls:'code'  }
};

// -------------------------------------------------------
// State
// -------------------------------------------------------
var useMaterial = true;

// Registry of all file nodes: path -> { checkbox, row }
// Populated during renderNode so we can drive them programmatically
var fileRegistry = {};

// -------------------------------------------------------
// Public API
// -------------------------------------------------------

/**
 * Returns an array of selected file paths.
 * Only file paths are returned — directories are never included,
 * they merely act as a convenience to select/deselect their children.
 *
 * Example usage:
 *   var paths = getSelectedPaths();
 *   // => ["/uwe-uat/direct-upload/BigUpload1.pdf", ...]
 *   fetch('/api/process', { method:'POST', body: JSON.stringify({ paths: paths }) });
 */
function getSelectedPaths() {
  var selected = [];
  for (var path in fileRegistry) {
    if (fileRegistry.hasOwnProperty(path) && fileRegistry[path].checkbox.checked) {
      selected.push(path);
    }
  }
  return selected;
}

// -------------------------------------------------------
// Helpers
// -------------------------------------------------------
function getName(path) {
  return path.split('/').filter(Boolean).pop() || path;
}

function getExt(name) {
  var parts = name ? name.split('.') : [];
  return parts.length > 1 ? parts[parts.length - 1].toLowerCase() : '';
}

function sortItems(items) {
  return items.slice().sort(function(a, b) {
    if (a.type === b.type) return getName(a.path).localeCompare(getName(b.path));
    return a.type === 'dir' ? -1 : 1;
  });
}

function makeIcon(isDir, ext, isOpen) {
  var el = document.createElement('span');
  el.className = 'tree-icon';
  if (useMaterial) {
    el.classList.add('mi');
    if (isDir) {
      el.classList.add(isOpen ? 'folder-open' : 'folder');
      el.textContent = isOpen ? 'folder_open' : 'folder';
    } else {
      var info = MATERIAL_FILE[ext] || { glyph:'insert_drive_file', cls:'generic' };
      el.classList.add(info.cls);
      el.textContent = info.glyph;
    }
  } else {
    el.textContent = isDir ? '📁' : (EMOJI_ICONS[ext] || '📄');
  }
  return el;
}

// -------------------------------------------------------
// Selection helpers
// -------------------------------------------------------

// Collect all file paths nested within an item (recursively)
function collectFilePaths(item, result) {
  if (item.type === 'file') {
    result.push(item.path);
  }
  if (item.children && item.children.length) {
    for (var i = 0; i < item.children.length; i++) {
      collectFilePaths(item.children[i], result);
    }
  }
}

// Set checked + highlight state for a single file entry
function setFileSelected(path, checked) {
  var entry = fileRegistry[path];
  if (!entry) return;
  entry.checkbox.checked = checked;
  if (checked) {
    entry.row.classList.add('selected');
  } else {
    entry.row.classList.remove('selected');
  }
}

// Derive and apply the indeterminate / checked state of a dir checkbox
// based on its descendant file checkboxes
function syncDirCheckbox(dirCheckbox, filePaths) {
  var total   = filePaths.length;
  var checked = 0;
  for (var i = 0; i < filePaths.length; i++) {
    var entry = fileRegistry[filePaths[i]];
    if (entry && entry.checkbox.checked) checked++;
  }
  if (checked === 0) {
    dirCheckbox.checked       = false;
    dirCheckbox.indeterminate = false;
  } else if (checked === total) {
    dirCheckbox.checked       = true;
    dirCheckbox.indeterminate = false;
  } else {
    dirCheckbox.checked       = false;
    dirCheckbox.indeterminate = true;
  }
}

// -------------------------------------------------------
// Render
// -------------------------------------------------------
function renderNode(item, container) {
  var isDir       = item.type === 'dir';
  var hasChildren = isDir && item.children && item.children.length > 0;
  var name        = getName(item.path);
  var ext         = isDir ? '' : getExt(name);

  // Collect descendant file paths once (used for dir checkbox logic)
  var filePaths = [];
  if (isDir) collectFilePaths(item, filePaths);

  var nodeEl = document.createElement('div');
  nodeEl.className = 'tree-node';

  var row = document.createElement('div');
  row.className = 'tree-row';

  // -- Expand/collapse arrow --
  var arrow = document.createElement('span');
  arrow.className = 'tree-arrow' + (hasChildren ? ' open' : ' leaf');
  arrow.textContent = '▶';

  // -- Checkbox --
  var checkbox = document.createElement('input');
  checkbox.type = 'checkbox';
  checkbox.className = 'tree-check';

  // -- Icon --
  var icon = makeIcon(isDir, ext, true);

  // -- Label --
  var label = document.createElement('span');
  label.className = 'tree-label ' + (isDir ? 'dir' : 'file');
  if (!isDir) {
    var base = ext ? name.slice(0, -(ext.length + 1)) : name;
    label.textContent = base;
    if (ext) {
      var extSpan = document.createElement('span');
      extSpan.className = 'tree-ext';
      extSpan.textContent = '.' + ext;
      label.appendChild(extSpan);
    }
  } else {
    label.textContent = name;
  }

  var metaSpan = document.createElement('span');
  metaSpan.className = 'meta';
  if (item.size) metaSpan.textContent = item.size;

  row.appendChild(arrow);
  row.appendChild(checkbox);
  row.appendChild(icon);
  row.appendChild(label);
  row.appendChild(metaSpan);
  nodeEl.appendChild(row);

  // -- Register file nodes --
  if (!isDir) {
    fileRegistry[item.path] = { checkbox: checkbox, row: row };
  }

  // -- Children --
  var childrenEl = null;
  if (hasChildren) {
    childrenEl = document.createElement('div');
    childrenEl.className = 'tree-children';
    var sorted = sortItems(item.children);
    for (var i = 0; i < sorted.length; i++) {
      renderNode(sorted[i], childrenEl);
    }
    nodeEl.appendChild(childrenEl);
  }

  // -- Checkbox change handler --
  checkbox.addEventListener('change', function(e) {
    e.stopPropagation(); // don't bubble to row click
    if (isDir) {
      // Select / deselect all descendant files
      var check = checkbox.checked;
      checkbox.indeterminate = false;
      for (var j = 0; j < filePaths.length; j++) {
        setFileSelected(filePaths[j], check);
      }
    } else {
      // Toggle this file's highlight
      if (checkbox.checked) {
        row.classList.add('selected');
      } else {
        row.classList.remove('selected');
      }
    }
  });

  // -- Row click: toggle checkbox (but not when clicking the checkbox itself) --
  row.addEventListener('click', function(e) {
    if (e.target === checkbox) return;
    if (e.target === arrow)    return;
    checkbox.checked = !checkbox.checked;
    checkbox.dispatchEvent(new Event('change'));
  });

  // -- Arrow click: expand/collapse only --
  if (hasChildren) {
    arrow.addEventListener('click', function(e) {
      e.stopPropagation();
      var open = arrow.classList.contains('open');
      if (open) {
        arrow.classList.remove('open');
        childrenEl.classList.add('collapsed');
        if (useMaterial) { icon.textContent = 'folder'; icon.className = 'tree-icon mi folder'; }
      } else {
        arrow.classList.add('open');
        childrenEl.classList.remove('collapsed');
        if (useMaterial) { icon.textContent = 'folder_open'; icon.className = 'tree-icon mi folder-open'; }
      }
    });
  }

  container.appendChild(nodeEl);
}

function renderAll(data) {
  fileRegistry = {};
  var rootEl = document.getElementById('arkivum_import');
  rootEl.innerHTML = '';
  var sorted = sortItems(data);
  for (var i = 0; i < sorted.length; i++) {
    renderNode(sorted[i], rootEl);
  }
}

// -------------------------------------------------------
// Expand / collapse all
// -------------------------------------------------------
function setAll(open) {
  var arrows   = document.querySelectorAll('.tree-arrow:not(.leaf)');
  var children = document.querySelectorAll('.tree-children');
  var folders  = document.querySelectorAll('.tree-icon.mi.folder, .tree-icon.mi.folder-open');
  for (var i = 0; i < arrows.length; i++) {
    if (open) arrows[i].classList.add('open'); else arrows[i].classList.remove('open');
  }
  for (var j = 0; j < children.length; j++) {
    if (open) children[j].classList.remove('collapsed'); else children[j].classList.add('collapsed');
  }
  if (useMaterial) {
    for (var k = 0; k < folders.length; k++) {
      if (open) { folders[k].textContent = 'folder_open'; folders[k].className = 'tree-icon mi folder-open'; }
      else      { folders[k].textContent = 'folder';      folders[k].className = 'tree-icon mi folder'; }
    }
  }
}

function expandAll()   { setAll(true);  }
function collapseAll() { setAll(false); }

// -------------------------------------------------------
// Toggle icon mode — re-renders the whole tree
// -------------------------------------------------------
function setIconMode(material) {
  useMaterial = material;
  renderAll();
}

