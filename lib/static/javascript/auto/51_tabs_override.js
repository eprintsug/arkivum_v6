window.ep_showTab = function( baseid, tabid, expensive )
{
    panels = $(baseid + "_panels");
    for( i=0; i < panels.childNodes.length; ++i){
      if(panels.childNodes[i].nodeType !== Node.ELEMENT_NODE) continue;
      Element.hide( panels.childNodes[i] );
    }

    tabs = $(baseid + "_tabs");
    for( i=0; i<tabs.childNodes.length; i++ )
    {
      if(tabs.childNodes[i].nodeType !== Node.ELEMENT_NODE) continue;
      Element.removeClassName( tabs.childNodes[i], 'active' );
    }

    panel = $(baseid+"_panel_"+tabid);

    panel.style.display = "block";

    tab = $(baseid+"_tab_"+tabid);
    tab.addClassName( "active" );

    anchors = tab.getElementsByTagName('a');
    for( i=0; i<anchors.length; i++ )
    {
        anchors[i].blur();
    }

    if(expensive && !panel.loaded)
    {
        var link = tab.down('a');
        link = link.href.split('?');
        new Ajax.Updater(panel, link[0], {
            onComplete: function() {
                panel.loaded = 1;
            },
            method: "get",
            evalScripts: true,
            parameters: 'ajax=1&' + link[1]
        });
    }

//  window.location.hash = 'ep_tabs:' + baseid + ':' + tabid;

    return false;
};
