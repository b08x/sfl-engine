# frozen_string_literal: true

# lib/sfl/gui/item_list_control.rb

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
            selected_item <=> [viewmodel, :modality_filter]

            on_selected { viewmodel.refresh! }
          }

          table {
            text_column("Modality")
            text_column("Reason")
            text_column("Source File")
            text_column("Created At")

            # rubocop:disable Layout/FirstArrayElementLineBreak, Layout/MultilineArrayLineBreaks, Layout/MultilineArrayBraceLayout
            cell_rows <= [viewmodel, :items, on_read: ->(items) {
              items.map { |item| [item[:modality], item[:reason], item[:source_file], item[:created_at].to_s] }
            }]
            # rubocop:enable Layout/FirstArrayElementLineBreak, Layout/MultilineArrayLineBreaks, Layout/MultilineArrayBraceLayout

            # Hands over the index and nothing else: resolving it to an item is
            # the viewmodel's job (SIFT S-2 — this used to reach through the
            # viewmodel into its own items array).
            on_row_clicked { |row| viewmodel.select_row(row) }
          }
        }
      }
    end
  end
end
