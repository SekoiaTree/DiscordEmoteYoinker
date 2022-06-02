extends VBoxContainer

var http : HTTPClient = HTTPClient.new()
var emoji_http : HTTPClient = HTTPClient.new()

enum State {
	WAITING,
	UPLOADING,
	DOWNLOADING
}

var has_started := false

var state = State.WAITING
var current_emoji := 0
var emojis
var images = []

onready var download_button = $Download/Button
onready var upload_button = $Upload/Button3

# Called when the node enters the scene tree for the first time.
func _ready():
	var err = http.connect_to_host("https://discord.com")
	assert(err == OK)
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		if not OS.has_feature("web"):
			OS.delay_msec(1)
		else:
			yield(Engine.get_main_loop(), "idle_frame")
	
	err = emoji_http.connect_to_host("https://cdn.discordapp.com")
	assert(err == OK)
	while emoji_http.get_status() == HTTPClient.STATUS_CONNECTING or emoji_http.get_status() == HTTPClient.STATUS_RESOLVING:
		emoji_http.poll()
		if not OS.has_feature("web"):
			OS.delay_msec(1)
		else:
			yield(Engine.get_main_loop(), "idle_frame")
	get_tree().create_timer(0.1).connect("timeout", self, "_on_resized")

# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass


func _on_Button_pressed():
	var token = $Token.get_text()
	var sourceID = $SourceServerID.get_text()
	for child in $ScrollContainer/GridContainer.get_children():
		child.queue_free()
	
	var rb = request_await("/api/v9/guilds/"+sourceID+"/emojis", token, http)
	var result = rb.get_string_from_utf8()
	var json = JSON.parse(result)
	if json.error:
		return #TODO
	
	result = json.result
	state = State.DOWNLOADING
	download_button.disabled = true
	upload_button.disabled = true
	images = []
	current_emoji = 0
	has_started = false
	emojis = result

func _process(delta):
	if state == State.WAITING:
		return
	if state == State.DOWNLOADING:
		download()
	elif state == State.UPLOADING:
		upload()

func upload():
	if http.get_status() == HTTPClient.STATUS_REQUESTING and has_started:
		http.poll()
		return
	
	
	if http.has_response():
		while http.get_status() == HTTPClient.STATUS_BODY:
			http.poll()
			var chunk = http.read_response_body_chunk()
			if chunk.size() == 0:
				if not OS.has_feature("web"):
					OS.delay_usec(1000)
				else:
					yield(Engine.get_main_loop(), "idle_frame")
	
	current_emoji += 1
	while current_emoji < emojis.size() && not $ScrollContainer/GridContainer.get_child(current_emoji).pressed:
		current_emoji += 1
	if current_emoji >= emojis.size():
		state = State.WAITING
		upload_button.disabled = false
		download_button.disabled = false
	else:
		var image_header = "data:image/png;base64,"
		if emojis[current_emoji]["animated"]:
			image_header = "data:image/gif;base64,"
		var encoded = {"name":emojis[current_emoji]["name"], "image":image_header+images[current_emoji]}
		var length = to_json(encoded).length()
		http.request(HTTPClient.METHOD_POST, "/api/v9/guilds/"+$TargetServerID.get_text()+"/emojis", ["authorization: "+$Token.get_text(), "content-type: application/json", "Content-length: "+str(length)], to_json(encoded))
		has_started = true

func download():
	if emoji_http.get_status() == HTTPClient.STATUS_REQUESTING and has_started:
		emoji_http.poll()
		return
	
	if not has_started:
		download_emoji()
		return
	
	var rb = get_from_client(emoji_http)
	
	var image = Image.new()
	var error = image.load_png_from_buffer(rb)
	if error != OK:
		push_error("Couldn't load the image")
	var texture = ImageTexture.new()
	texture.flags = texture.flags & ~ImageTexture.FLAG_FILTER
	texture.create_from_image(image)
	var emoji_scene = preload("res://Emoji.tscn").instance()
	emoji_scene.set_texture(texture)
	emoji_scene.set_name(emojis[current_emoji]["name"])
	emoji_scene.set_gif(emojis[current_emoji]["animated"])
	
	if emojis[current_emoji]["animated"]:
		images.append(Marshalls.raw_to_base64(request_await("/emojis/"+emojis[current_emoji]["id"]+".gif", "", emoji_http, false)))
	else:
		images.append(Marshalls.raw_to_base64(rb))
	$ScrollContainer/GridContainer.add_child(emoji_scene)
	emoji_scene.connect("pressed", $ScrollContainer/GridContainer, "child_pressed", [current_emoji])
	current_emoji += 1
	if current_emoji >= emojis.size():
		state = State.WAITING
		download_button.disabled = false
		upload_button.disabled = false
	else:
		download_emoji()

func download_emoji():
	request("/emojis/"+emojis[current_emoji]["id"]+".png", emoji_http)
	has_started = true

func get_from_client(client : HTTPClient):
	var rb = PoolByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		# While there is body left to be read
		client.poll()
		# Get a chunk.
		var chunk = client.read_response_body_chunk()
		if chunk.size() == 0:
			if not OS.has_feature("web"):
				# Got nothing, wait for buffers to fill a bit.
				OS.delay_usec(1000)
			else:
				yield(Engine.get_main_loop(), "idle_frame")
		else:
			rb = rb + chunk # Append to read buffer.
	return rb

func request(path : String, client : HTTPClient):
	var err = client.request(HTTPClient.METHOD_GET, path, [])
	assert(err == OK)

func request_await(path : String, token : String, client : HTTPClient, auth : bool = true):
	var err
	if auth:
		err = client.request(HTTPClient.METHOD_GET, path, ["authorization: "+token])
	else:
		err = client.request(HTTPClient.METHOD_GET, path, [])
	assert(err == OK)
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		# Keep polling for as long as the request is being processed.
		client.poll()
		if OS.has_feature("web"):
			# Synchronous HTTP requests are not supported on the web,
			# so wait for the next main loop iteration.
			yield(Engine.get_main_loop(), "idle_frame")
		else:
			OS.delay_usec(500)
	assert(client.get_status() == HTTPClient.STATUS_BODY or client.get_status() == HTTPClient.STATUS_CONNECTED) # Make sure request finished well.
	
	if client.has_response():
		var rb = PoolByteArray()
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk = client.read_response_body_chunk()
			if chunk.size() == 0:
				if not OS.has_feature("web"):
					OS.delay_usec(1000)
				else:
					yield(Engine.get_main_loop(), "idle_frame")
			else:
				rb = rb + chunk
		return rb
	else:
		return null

func _on_resized():
	$ScrollContainer/GridContainer.columns = rect_size.x/48-2

func start_uploading():
	state = State.UPLOADING
	download_button.disabled = true
	upload_button.disabled = true
	current_emoji = -1
	has_started = false
