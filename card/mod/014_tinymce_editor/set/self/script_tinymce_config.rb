include_set Abstract::CodeFile

Self::ScriptEditors.add_to_basket :item_codenames, :script_tinymce_config
Self::Head::Javascript::HtmlFormat.add_to_basket :mod_js_config,
                                                 [:ace, 'setTinyMCEConfig']
