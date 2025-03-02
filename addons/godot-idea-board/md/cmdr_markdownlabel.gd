@tool
extends MarkdownLabel

#const MAX_IMAGE_WIDTH := 512 # Cmdr: Set in original markdownlabel
#const LARGE_IMG_FILE_PREFIX := "CMDR_XL__"
#const LARGE_IMG_FILE_MIN_WIDTH := 512

const error_url := "res://tools/StatusError.png"
const ALLOWED_IMAGE_FILETYPES := ["bmp", "jpg", "ktx", "png", "svg", "tga", "webp"]
const ALLOWED_IMAGE_MIMETYPES := ["image/bmp", "image/jpeg", "image/ktx", "image/png", "image/svg", "image/tga", "image/webp"]
const MAX_IMAGES := 64

var img_save_path := "res://temp/idea-board_images/"

var http_request: HTTPRequest

var current_file_name := "unnamed"
var current_header_name := "CommentNodeUnnamed"

var git_main_url := "https://github.com/"
var git_cdn_url := "https://raw.githubusercontent.com/"
var git_cdn_repo_url := ""
var branch_url_prefix = "HEAD/" # "/refs/heads/main/"
var default_readme_file = "README.md"

# Used for importing
var new_images_saved: bool = false

# Temp
var cur_url: String = ""
var cur_res_path: String = ""
var cur_readme_text: String = ""

func _ready() -> void:
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(self._http_request_completed)
	super()

func _cleanup_and_set_git_url(input_url: String) -> String:
	var _ret: String = ""
	if input_url.begins_with(git_main_url):
		var header_url_parts = input_url.replace(git_main_url, "").split("/")
		var core_repo_url = git_main_url.path_join(header_url_parts[0]).path_join(header_url_parts[1])
		var core_cdn_repo_url = git_cdn_url.path_join(header_url_parts[0]).path_join(header_url_parts[1])
		git_cdn_repo_url = core_cdn_repo_url.path_join(branch_url_prefix)
		_ret = core_repo_url
	return _ret

# Preprocess
func _convert_markdown(source_text = "") -> String:
	var orig_text = text
	text = "Loading Images..."
	var text_edit_sibling = get_node_or_null("../TextEdit")
	if not text_edit_sibling: 
		# If text_edit_sibling and thus Parent is not avail
		# then _ready is prob not called and we ignore these init calls
		return super(source_text)
	if current_header_name.begins_with(git_main_url):
		var cleaned_repo_url = _cleanup_and_set_git_url(current_header_name)
		var _comment_parent = get_node_or_null("../../../") # CommentNode
		if _comment_parent && _comment_parent.has_method("change_header_text"):
			_comment_parent.change_header_text(cleaned_repo_url)
			current_header_name = cleaned_repo_url
		
		if text_edit_sibling.text == "":
			var url = git_cdn_repo_url.path_join(default_readme_file)
			print("requesting ", url)
			# Download README.md
			if _get_http_file(url):
				await http_request.request_completed
				source_text = cur_readme_text
				if text_edit_sibling:
					text_edit_sibling.text = cur_readme_text
				#push_warning(source_text)
	var first_newline_idx = source_text.find("\n")
	var first_line = source_text.substr(0, first_newline_idx)
	if first_line.begins_with(git_main_url):
		var cleaned_repo_url = _cleanup_and_set_git_url(first_line)
		source_text = cleaned_repo_url + source_text.substr(first_newline_idx)
		
	var cstart_index := 0
	var regex := RegEx.new()
	var html_img_pattern = r"<img.*?src=[\"|'](.*?)[\"|']"
	regex.compile(html_img_pattern)
	var html_tags: Array[Array] = []
	for result in regex.search_all(source_text):
		var tag_end = source_text.find(">", result.get_start()) + 1
		var full_tag = source_text.substr(result.get_start(), tag_end - result.get_start())
		var md_tag = "![img](%s)" % result.get_string(1)
		print("replacing ", full_tag, " with ", md_tag)
		html_tags.append([full_tag, md_tag])
	
	for tag: Array in html_tags:
		source_text = source_text.replacen(tag[0], tag[1])

	var img_pattern := r"!\[(.*?)\]\((.*?)[\s|\)]" # Oh man.... so we find any ![*](* followed by ) or \s for space incase image has title
	regex.compile(img_pattern)
	var all_urls: Array[String] = []
	for result in regex.search_all(source_text):
		all_urls.push_back(result.get_string(2))
		
		#print(all_urls)
	for curl: String in all_urls:
		var new_url = await _http_to_res_link(curl)
		if curl != new_url:
			source_text = source_text.replacen(curl, new_url)
			#push_warning(new_url)
	
	if new_images_saved:
		EditorInterface.get_resource_filesystem().scan()
		#await get_tree().create_timer(8).timeout
		
	#scroll_to_line(0)
	text = orig_text
	#print(size.x)
	return super(source_text)

func _http_to_res_link(url: String) -> String:
	# Return res:// links etc as is
	if url.begins_with("res://"):
		return url
	
	if git_cdn_repo_url != "" && url.find("://") == -1:
		if url.begins_with("./"): 
			url = url.substr(2)
		url = git_cdn_repo_url.path_join(url)
	print(url)
		
	if url.begins_with("https://"):
		# Check if img was already downloaded
		var size_prefixes := ["", LARGE_IMG_FILE_PREFIX]
		for s_prefix: String in size_prefixes:
			var new_img_path = img_save_path.path_join(s_prefix + url.validate_filename() + ".res") # .path_join(current_file_name.replace(".json", "").path_join(current_header_name.validate_filename()).path_join(s_prefix + url.get_file().validate_filename() + ".res"))
			if FileAccess.file_exists(new_img_path):
				print("Img already found")
				return new_img_path
		
		# Download Image
		if _get_http_file(url):
			await http_request.request_completed
			return cur_res_path
		else:
			return error_url
	else:
		return error_url

func _get_http_file(url: String) -> bool:
	# Create an HTTP request node and connect its completion signal.
	# Perform the HTTP request. The URL below returns a PNG image as of writing.
	cur_url = url
	print("requesting ", url)
	var error = http_request.request(url)
	if error != OK:
		cur_url = ""
		push_error("An error occurred in the HTTP request.")
	return(error == OK)

func _load_image_from_buffer(extension: String, img: Image, bytes: PackedByteArray) -> Error:
	var method_to_call = "load_" + extension + "_from_buffer"
	assert(img.has_method(method_to_call))
	return img.call(method_to_call, bytes)

# Called when the HTTP request is completed.
func _http_request_completed(result, response_code, headers, body) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Image couldn't be downloaded. Try a different image.")
		cur_res_path = error_url
	elif cur_url.get_file() == default_readme_file:
		push_warning("README DETECTED")
		cur_readme_text = body.get_string_from_utf8()
	else:
		var cur_file_extension = cur_url.get_extension()
		if cur_file_extension == "gif": # Content-Type is sometimes application/octet-stream
			var texture: AnimatedTexture = GifManager.animated_texture_from_buffer(body)
			save_texture_to_disk(texture, ".res")
		else:
			for header: String in headers:
				if header.begins_with("Content-Type:"):
					#push_warning("ext: " + cur_file_extension + " | Header: " + header)
					for mime_idx: int in range(ALLOWED_IMAGE_MIMETYPES.size()):
						if header.containsn(ALLOWED_IMAGE_MIMETYPES[mime_idx]):
							cur_file_extension = ALLOWED_IMAGE_FILETYPES[mime_idx]
							break
					break
			#printt(cur_url, cur_file_extension)
			if cur_file_extension in ALLOWED_IMAGE_FILETYPES:
				var image = Image.new()
				var error = _load_image_from_buffer(cur_file_extension, image, body)
				if error != OK:
					push_error("Couldn't load the image.")
					cur_res_path = error_url
				else:
					var texture = ImageTexture.create_from_image(image)
					save_texture_to_disk(texture, ".res")
			else:
				push_warning("unsupported filetype: ", cur_file_extension)
				cur_res_path = error_url
	#return "texture"
	
func save_texture_to_disk(texture: Texture2D, file_extension: String = ".res") -> Error:
	var folder_path = img_save_path#.path_join(current_file_name.replace(".json", "")).path_join(current_header_name.validate_filename()))
	if not DirAccess.dir_exists_absolute(folder_path):
		DirAccess.make_dir_recursive_absolute(folder_path)
	var size_prefix = LARGE_IMG_FILE_PREFIX if texture.get_width() >= LARGE_IMG_FILE_MIN_WIDTH else ""
	var new_img_filename = size_prefix + cur_url.validate_filename()
	new_img_filename += file_extension
	#if not new_img_filename.ends_with(cur_file_extension):
		#new_img_filename += "." + cur_file_extension
	var new_img_path = folder_path.path_join(new_img_filename)
	#print(new_img_path)
	#print(ResourceSaver.get_recognized_extensions(texture))
	var save_error = ResourceSaver.save(texture, new_img_path)
	#print(save_error)
	if save_error == OK:
		push_warning("Saved image: ", new_img_path)
		cur_res_path = new_img_path
		new_images_saved = true
	else:
		push_warning("Save Error: ", error_string(save_error))
		cur_res_path = error_url
	return save_error
