add_to_basket(
  :tasks,
  [:update_file_storage_locations,
   {
     execute_policy: -> { Card.update_all_storage_locations },
     stats_policy: lambda do
       ["cards with attachment",
        { count: Card.search(type_id: ["in", FileID, ImageID],
                             return: :count),
          link_text: "update storage locations",
          task: "update_file_storage_locations" }]
     end
   }]
)

add_to_basket(
  :tasks,
  [:delete_upload_tmp_files,
   {
     execute_policy: -> { Card.delete_tmp_files_of_cached_uploads },
     stats_policy: lambda do
       ["tmp files of canceled uploads",
        { count: ::Card.draft_actions_with_attachment,
          link_text: "delete tmp files",
          task: "delete_tmp_files_of_cached_uploads" }]
     end
   }]
)
