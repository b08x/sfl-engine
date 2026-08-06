# lib/sfl/gui/item_list_control.rb
# frozen_string_literal: true

module SFL
  module GUI
    # Left pane: a modality filter and the table of pending review_queue rows.
    # Selecting a row calls viewmodel.select — every other control reacts to
    # that via data-binding, this control never talks to them directly.
    class ItemListControl
      include Glimmer::LibUI::CustomControl

      options :viewmodel

      body {
        vertical_box {
          combobox {
            items %w[all image text audio]
            # rubocop:disable Lint/Void
            selected_item <=> [viewmodel, :modality_filter]
            # rubocop:enable Lint/Void

            on_selected { viewmodel.refresh! }
          }

          table {
            text_column("Modality")
            text_column("Reason")
            text_column("Source File")
            text_column("Created At")

            # rubocop:disable Lint/Void, Layout/FirstArrayElementLineBreak, Layout/MultilineArrayLineBreaks, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral, Style/Lambda, Layout/MultilineArrayBraceLayout
            cell_rows <= [viewmodel, :items, on_read: ->(items) {
              items.map { |item| [item[:modality], item[:reason], item[:source_file], item[:created_at].to_s] }
            }]
            # rubocop:enable Lint/Void, Layout/FirstArrayElementLineBreak, Layout/MultilineArrayLineBreaks, Style/HashAsLastArrayItem, Layout/SpaceInLambdaLiteral, Style/Lambda, Layout/MultilineArrayBraceLayout

            on_row_clicked { |row| viewmodel.select(viewmodel.items[row]) }
          }
        }
      }
    end
  end
end
