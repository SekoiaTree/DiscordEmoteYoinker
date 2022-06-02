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
onready var error_text = $Label

# Called when the node enters the scene tree for the first time.
func _ready():
	var err = -1
	while err != OK:
		err = http.connect_to_host("https://discord.com")
		OS.delay_msec(1)
	
	var ready = false
	while http.get_status() == HTTPClient.STATUS_DISCONNECTED or not ready:
		ready = true
		while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
			http.poll()
			OS.delay_msec(1)
		if http.get_status() == HTTPClient.STATUS_DISCONNECTED:
			OS.delay_msec(200)
	
	err = -1
	while err != OK:
		err = emoji_http.connect_to_host("https://cdn.discordapp.com")
		OS.delay_msec(1)
	
	ready = false
	while emoji_http.get_status() == HTTPClient.STATUS_DISCONNECTED or not ready:
		ready = true
		while emoji_http.get_status() == HTTPClient.STATUS_CONNECTING or emoji_http.get_status() == HTTPClient.STATUS_RESOLVING:
			emoji_http.poll()
			OS.delay_msec(1)
		
		if emoji_http.get_status() == HTTPClient.STATUS_DISCONNECTED:
			OS.delay_msec(200)
	
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
	if json.error != OK:
		error_text.display_error("Could not parse JSON!")
		return
	
	result = json.result
	
	if not result is Array:
		error_text.display_error("Failed to fetch emojis. Check if you inputted your data correctly, then try again.")
		return
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
				OS.delay_usec(1000)
		if http.get_response_code() < 200 or http.get_response_code() >= 300:
			error_text.display_error("Failed to send request, with code " + str(http.get_response_code())+". This probably disconnected us, so you'll have to restart. Sorry!")
			get_tree().paused = true
			return
	
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
		error_text.display_error("Couldn't load image!")
		return
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
			OS.delay_usec(1000)
		else:
			rb = rb + chunk # Append to read buffer.
	return rb

func request(path : String, client : HTTPClient):
	var err = client.request(HTTPClient.METHOD_GET, path, [])
	if err != OK:
		error_text.display_error("Failed to request! You'll have to restart, sorry!")
		get_tree().paused = true

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
		OS.delay_usec(500)
	
	if client.has_response():
		var rb = PoolByteArray()
		while client.get_status() == HTTPClient.STATUS_BODY:
			client.poll()
			var chunk = client.read_response_body_chunk()
			if chunk.size() == 0:
				OS.delay_usec(1000)
			else:
				rb = rb + chunk
		return rb
	else:
		error_text.display_error("Failed to get something, no response received. Sorry!")
		return null

func _on_resized():
	$ScrollContainer/GridContainer.columns = rect_size.x/48-2

func start_uploading():
	state = State.UPLOADING
	download_button.disabled = true
	upload_button.disabled = true
	current_emoji = -1
	has_started = false
