extends Node 


class_name Dispatcher

@export var updateFrequency: int = 1
@export var autoStart:bool
@export var dataTexture:Texture2D
@export var dataDead:Texture2D
@export var dataGreen:Texture2D


var size = 128
@export_file var computeShader: String = "res://gol.glsl"
@onready var renderer: Sprite2D = $"../renderer"

var rd: RenderingDevice
var inputTexture : RID 
var outputTexture : RID 
var deadTexture : RID
var greenTexture: RID

var uniformSet : RID 
var shader : RID 
var pipeline : RID 

var inputUniform: RDUniform
var outputUniform: RDUniform
var bindings: Array[RDUniform]

var inputImage:Image
var outputImage:Image
var deadImage:Image
var greenImage:Image
var renderTexture: ImageTexture
var renderDeadTexture: ImageTexture
var renderGreenTexture: ImageTexture

var inputFormat: RDTextureFormat
var outputFormat: RDTextureFormat
var processing: bool

@warning_ignore("int_as_enum_without_cast")
@warning_ignore("int_as_enum_without_match")
var textureUsage: RenderingDevice.TextureUsageBits = \
	RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
	+ RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
	+ RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
func _ready() -> void:
	create_and_validate_images()
	setup_compute_shader()
	
	if !autoStart:
		return
		
	start_process_loop()
	pass
	
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event = event as InputEventKey
		if key_event.keycode == KEY_SPACE and key_event.pressed:
			if processing:
				processing = false
			else:
				start_process_loop()
		if key_event.keycode == KEY_ESCAPE and key_event.pressed:
			if processing:
				processing = false
			get_tree().quit()
	
	pass
	
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		cleanup()


func mergeImage():
	var outputWidth = outputImage.get_width()
	var outputHeight = outputImage.get_height()
	
	var inputWidth = inputImage.get_width()
	var inputHeight = inputImage.get_height()
	
	@warning_ignore("integer_division")
	var startX = (outputWidth - inputWidth) /2
	@warning_ignore("integer_division")
	var startY = (outputHeight - inputHeight) /2
	
	for x in range(inputWidth):
		for y in range(inputHeight):
			var color = inputImage.get_pixel(x,y)
			
			var destX = startX + x
			var destY = startY + y

			if destX >= 0 and destX < outputWidth and destY >= 0 and destY < outputHeight:
				outputImage.set_pixel(destX, destY, color)
	
	inputImage.set_data(size,size,false,Image.FORMAT_L8,outputImage.get_data())
	pass
	
func link_output_texture_to_renderer():
	var mat = renderer.material as ShaderMaterial
	
	renderTexture = ImageTexture.create_from_image(outputImage)
	renderDeadTexture = ImageTexture.create_from_image(deadImage)
	renderGreenTexture = ImageTexture.create_from_image(greenImage)
	if mat:
		mat.set_shader_parameter("binaryDataTexture",renderTexture)
		mat.set_shader_parameter("deadzoneDataTexture",renderDeadTexture)
		mat.set_shader_parameter("greenDataTexture",renderGreenTexture)


func create_and_validate_images():
	outputImage = Image.create(size,size,false,Image.FORMAT_L8)
	if dataTexture == null:
		var noise = FastNoiseLite.new()
		noise.frequency = 0.1
		
		var noise_image = noise.get_image(size,size)
		inputImage = noise_image
	else:
		inputImage = dataTexture.get_image()
	
	if dataDead == null:
		var noise = FastNoiseLite.new()
		noise.frequency = 0.1
		
		var noise_image = noise.get_image(size,size)
		deadImage = noise_image
	else:
		deadImage = dataDead.get_image()
	
	if dataGreen == null:
		var noise = FastNoiseLite.new()
		noise.frequency = 0.1
		
		var noise_image = noise.get_image(size,size)
		greenImage = noise_image
	else:
		greenImage = dataGreen.get_image()
		
		
	mergeImage()
	link_output_texture_to_renderer()
		
	pass

func create_rendering_device():
	rd = RenderingServer.create_local_rendering_device()
	assert(rd != null, "Failed to create local rendering device")
	
func create_shader():
	var shader_file = load(computeShader) as RDShaderFile
	if shader_file == null:
		assert(false)
	var spirv:RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	if !shader.is_valid():
		assert(false)


func create_pipeline():
	pipeline = rd.compute_pipeline_create(shader)
	
func default_texture_format()->RDTextureFormat:
	var temp:RDTextureFormat = RDTextureFormat.new()
	temp.width = size
	temp.height = size
	temp.format = RenderingDevice.DATA_FORMAT_R8_UNORM
	temp.usage_bits = textureUsage

	return temp

func create_texture_format():
	inputFormat = default_texture_format()
	outputFormat= default_texture_format()
	
func create_texture_and_uniform(image:Image, format:RDTextureFormat,binding:int)->RID:
	var view = RDTextureView.new()
	var data = [image.get_data()]
	
	var texture:RID = rd.texture_create(format,view,data)
	
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = binding
	
	uniform.add_id(texture)
	bindings.append(uniform)
	
	return texture
	
func create_uniforms():
	inputTexture = create_texture_and_uniform(inputImage,inputFormat, 0)
	outputTexture = create_texture_and_uniform(outputImage,outputFormat, 1)
	deadTexture = create_texture_and_uniform(deadImage, inputFormat,2)
	greenTexture = create_texture_and_uniform(greenImage, inputFormat,3)
	
	
	uniformSet = rd.uniform_set_create(bindings, shader, 0)


func setup_compute_shader():
	create_rendering_device()
	create_shader()
	create_pipeline()
	create_texture_format()
	create_uniforms()
	
	
func start_process_loop():
	processing = true
	
	while processing:
		Update()
		await get_tree().create_timer(1 / updateFrequency).timeout
		Render()
		
func Update():
	var compute_list= rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list,pipeline)
	rd.compute_list_bind_uniform_set(compute_list,uniformSet,0)
	rd.compute_list_dispatch(compute_list,32,32,1)
	rd.compute_list_end()
	rd.submit()
	
	pass
	
	
func Render():
	rd.sync()
	var bytes = rd.texture_get_data(outputTexture,0)
	rd.texture_update(inputTexture,0,bytes)
	
	outputImage.set_data(size,size,false,Image.FORMAT_L8,bytes)
	
	renderTexture.update(outputImage)
		
	pass
	
func cleanup():
	if rd == null:
		return
	rd.free_rid(inputTexture)
	rd.free_rid(outputTexture)
	rd.free_rid(deadImage)
	rd.free_rid(greenImage)
	rd.free_rid(uniformSet)
	rd.free_rid(pipeline)
	rd.free_rid(shader)
	rd.free()
	rd = null
	pass
