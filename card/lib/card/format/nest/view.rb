class Card
  class Format
    module Nest
      NEST_MODES = { new: :edit,
                     closed_content: :closed,
                     setup: :edit,
                     edit: :edit, closed: :closed, layout: :layout,
                     normal: :normal, template: :template }.freeze

      # Renders views for a nests
      module View
        def with_nest_mode mode
          old_mode = @mode
          if (switch_mode = NEST_MODES[mode])
            @mode = switch_mode
          end
          result = yield
          @mode = old_mode
          result
        end

        # private

        def modal_nest_view view
          # Note: the subformat always has the same @mode as its parent format
          case @mode
          when :edit then view_in_edit_mode(view)
          when :template then :template_rule
          when :closed then view_in_closed_mode(view)
          else view
          end
        end

        # Returns the view that the card should use
        # if nested in edit mode
        def view_in_edit_mode homeview
          hide_view_in_edit_mode?(homeview) ? :blank : :edit_in_form
        end

        def hide_view_in_edit_mode? view
          Card::Format.perms[view] == :none || # view never edited
            card.structure                  || # not yet nesting structures
            card.key.blank?                    # eg {{_self|type}} on new cards
        end

        # Return the view that the card should use
        # if nested in closed mode
        def view_in_closed_mode view
          approved_view = Card::Format.closed[view]
          if approved_view == true
            view
          elsif Card::Format.error_code[view]
            view
          elsif approved_view
            approved_view
          elsif !card.known?
            :closed_missing
          else
            :closed_content
          end
        end
      end
    end
  end
end
