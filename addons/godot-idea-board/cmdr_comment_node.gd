@tool
class_name CommanderSekkeiCommentNode
extends SekkeiCommentNode

func change_header_text(new_header: String) -> void:
	header_line_edit.text = new_header

func _header_text_changed(new_text: String) -> void:
	parsed_rich_text_label.current_header_name = new_text

# Called when the node enters the scene tree for the first time.
func init(data:Dictionary = {}):
	header_line_edit.text_changed.connect(_header_text_changed)
	# Cmdr: Default Header Name
	if data.has("header_text"):
		header_line_edit.text = data.header_text
	else:
		header_line_edit.text = name
	parsed_rich_text_label.current_header_name = header_line_edit.text
	parsed_rich_text_label.current_file_name = get_parent().save_json_file_path.get_file()
	super(data)
