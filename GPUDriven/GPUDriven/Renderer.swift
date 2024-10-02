import MetalKit

class Renderer: NSObject {
    static var device: MTLDevice!
    static var cmdQ: MTLCommandQueue!
    static var lib: MTLLibrary!
    
    var uniforms = Uniforms()
    var fragUniforms = FragmentUniforms()
    var modelParams = ModelParams()
    
    let depthStencilState: MTLDepthStencilState
    
    var uniformsBuf: MTLBuffer!
    var fragmentUniformsBuf: MTLBuffer!
    var modelParamsBuf: MTLBuffer!
    
    var icb: MTLIndirectCommandBuffer!
    let icbComputeFunction: MTLFunction
    let icbPipelineState: MTLComputePipelineState
    var icbBuf: MTLBuffer!
    var modelsBuf: MTLBuffer!
    var drawArgBuf: MTLBuffer!

    
    lazy var camera: Camera = {
        let camera = ArcballCamera()
        camera.distance = 4.3
        camera.target = [0, 1.2, 0]
        camera.rotation.x = Float(-10).degreesToRadians
        return camera
    } ()
    
    
    var models: [Model] = []
    
    init(metalView: MTKView) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let cmdQ = device.makeCommandQueue() else {
                fatalError("GPU not available")
        }
        
        Renderer.device = device
        Renderer.cmdQ = cmdQ
        Renderer.lib = device.makeDefaultLibrary()
        metalView.device = device
        metalView.depthStencilPixelFormat = .depth32Float
        
        depthStencilState = Renderer.buildDepthStencilState()!
        icbComputeFunction = Renderer.lib.makeFunction(name: "encodeCommands")!
        icbPipelineState = Renderer.buildComputePipelineState(function: icbComputeFunction)
        
        super.init()
        metalView.clearColor = MTLClearColor(red: 0.7, green: 0.9,
                                            blue: 1.0, alpha: 1)
        
        metalView.delegate = self
        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
        
        let house = Model(name: "lowpoly-house.obj")
        house.rotation = [0, .pi/4, 0]
        models.append(house)
        
        let ground = Model(name: "plane.obj")
        ground.scale = [40, 40, 40]
        ground.tiling = 16
        models.append(ground)
        
        initialize()
        initializeCommands()
    }
    
    
    func initialize() {
        TextureController.heap = TextureController.buildHeap()
        
        models.forEach { model in
            model.initializeTextures()
        }

        var bufLen = MemoryLayout<Uniforms>.stride
        uniformsBuf = Renderer.device.makeBuffer(length: bufLen)
        uniformsBuf.label = "Uniforms"
        
        bufLen = MemoryLayout<FragmentUniforms>.stride
        fragmentUniformsBuf = Renderer.device.makeBuffer(length: bufLen)
        fragmentUniformsBuf.label = "Fragment Uniforms"
        
        bufLen = models.count * MemoryLayout<ModelParams>.stride
        modelParamsBuf = Renderer.device.makeBuffer(length: bufLen)
        modelParamsBuf.label = "Model Parameters"
    }
    
    func initializeCommands() {
        let icbDesc = MTLIndirectCommandBufferDescriptor()
        icbDesc.commandTypes = [.drawIndexed]
        icbDesc.inheritBuffers = false
        icbDesc.maxVertexBufferBindCount = 25
        icbDesc.maxFragmentBufferBindCount = 25
        icbDesc.inheritPipelineState = false
        
        guard let icb = Renderer.device.makeIndirectCommandBuffer(descriptor: icbDesc,
                                                             maxCommandCount: models.count) else { fatalError() }
        
        self.icb = icb
        
        let icbEncoder = icbComputeFunction.makeArgumentEncoder(bufferIndex: Int(BufferIndexICB.rawValue))
        icbBuf = Renderer.device.makeBuffer(length: icbEncoder.encodedLength)
        icbEncoder.setArgumentBuffer(icbBuf, offset: 0)
        icbEncoder.setIndirectCommandBuffer(icb, index: 0)
        
        var mBufs: [MTLBuffer] = []
        var mBufsLen = 0
        
        for model in models {
            let modelEncoder = icbComputeFunction.makeArgumentEncoder(bufferIndex: Int(BufferIndexModels.rawValue))
            let argBuf = Renderer.device.makeBuffer(length: modelEncoder.encodedLength)!
            
            modelEncoder.setArgumentBuffer(argBuf, offset: 0)
            modelEncoder.setBuffer(model.vertexBuffer, offset: 0, index: 0)
            modelEncoder.setBuffer(model.submesh.indexBuffer.buffer, offset: 0, index: 1)
            modelEncoder.setBuffer(model.texturesBuffer!, offset: 0, index: 2)
            modelEncoder.setRenderPipelineState(model.pipelineState, index: 3)
            
            mBufs.append(argBuf)
            mBufsLen += argBuf.length
        }
        
        //copy to self.modelsBuf
        modelsBuf = Renderer.device.makeBuffer(length: mBufsLen)
        modelsBuf.label = "Models Array Buffer"
        var offset = 0
        
        for mBuf in mBufs {
            var ptr = modelsBuf.contents()
            ptr = ptr.advanced(by: offset)
            ptr.copyMemory(from: mBuf.contents(), byteCount: mBuf.length)
            offset += mBuf.length
        }
        
        
        let drawLen = models.count * MemoryLayout<MTLDrawIndexedPrimitivesIndirectArguments>.stride
        drawArgBuf = Renderer.device.makeBuffer(length: drawLen)
        drawArgBuf.label = "Draw Arguments"
        
        var drawArgBufPtr = drawArgBuf.contents().bindMemory(to: MTLDrawIndexedPrimitivesIndirectArguments.self,
                                                       capacity: models.count)
        
        for (modelIdx, model) in models.enumerated() {
            var drawArg = MTLDrawIndexedPrimitivesIndirectArguments()
            drawArg.indexCount = UInt32(model.submesh.indexCount)
            drawArg.instanceCount = 1
            drawArg.indexStart = UInt32(model.submesh.indexBuffer.offset)
            drawArg.baseVertex = 0
            drawArg.baseInstance = UInt32(modelIdx)
            
            drawArgBufPtr.pointee = drawArg
            drawArgBufPtr = drawArgBufPtr.advanced(by: 1)
        }
        
    }

    static func buildDepthStencilState() -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return Renderer.device.makeDepthStencilState(descriptor: descriptor)
    }
    
    static func buildComputePipelineState(function: MTLFunction) -> MTLComputePipelineState {
        let computePipelineState: MTLComputePipelineState
        
        do {
            computePipelineState = try Renderer.device.makeComputePipelineState(function: function)
        } catch {
            fatalError(error.localizedDescription)
        }
        
        return computePipelineState
    }
}


extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspect = Float(view.bounds.width)/Float(view.bounds.height)
    }
    
    func draw(in view: MTKView) {
        guard
            let renderDesc = view.currentRenderPassDescriptor,
            let cmdBuf = Renderer.cmdQ.makeCommandBuffer() else {
                return
            }

        updateUniforms()
      
        guard
            let computeEncoder = cmdBuf.makeComputeCommandEncoder() else {
                return
            }
      
        computeEncoder.setComputePipelineState(icbPipelineState)
        
        computeEncoder.setBuffer(uniformsBuf,
                                 offset: 0,
                                 index: Int(BufferIndexUniforms.rawValue))
        
        computeEncoder.setBuffer(fragmentUniformsBuf,
                                 offset: 0,
                                 index: Int(BufferIndexFragmentUniforms.rawValue))
        
        computeEncoder.setBuffer(drawArgBuf, 
                                 offset: 0,
                                 index: Int(BufferIndexDrawArguments.rawValue))
        
        computeEncoder.setBuffer(modelParamsBuf, 
                                 offset: 0,
                                 index: Int(BufferIndexModelParams.rawValue))
        
        computeEncoder.setBuffer(modelsBuf, 
                                 offset: 0,
                                 index: Int(BufferIndexModels.rawValue))
        
        computeEncoder.setBuffer(icbBuf, 
                                 offset: 0,
                                 index: Int(BufferIndexICB.rawValue))
      
        computeEncoder.useResource(icb, usage: .write)
        computeEncoder.useResource(modelsBuf, usage: .read)

        if let heap = TextureController.heap {
            computeEncoder.useHeap(heap)
        }

        for model in models {
            computeEncoder.useResource(model.vertexBuffer, usage: .read)
            computeEncoder.useResource(model.submesh.indexBuffer.buffer, usage: .read)
            computeEncoder.useResource(model.texturesBuffer!, usage: .read)
        }
        
        
        let threadExecutionWidth = icbPipelineState.threadExecutionWidth
        let threads = MTLSize(width: models.count, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: threadExecutionWidth, height: 1, depth: 1)
        computeEncoder.dispatchThreads(threads, threadsPerThreadgroup: threadsPerThreadgroup)
        computeEncoder.endEncoding()

        let blitEncoder = cmdBuf.makeBlitCommandEncoder()!
        blitEncoder.optimizeIndirectCommandBuffer(icb, range: 0..<models.count)
        blitEncoder.endEncoding()
      
        guard let renderEncoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderDesc) else { 
            return
        }
        
        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.executeCommandsInBuffer(icb, range: 0..<models.count)
        renderEncoder.endEncoding()
        
        guard let drawable = view.currentDrawable else { return }
        
        cmdBuf.present(drawable)
        cmdBuf.commit()
    }

    
    func updateUniforms() {
        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix
        fragUniforms.cameraPosition = camera.position
        
        var bufLen = MemoryLayout<Uniforms>.stride
        uniformsBuf.contents().copyMemory(from: &uniforms, byteCount: bufLen)
        
        bufLen = MemoryLayout<FragmentUniforms>.stride
        fragmentUniformsBuf.contents().copyMemory(from: &fragUniforms, byteCount: bufLen)
        
        var modelParamsPtr = modelParamsBuf.contents().bindMemory(to: ModelParams.self, 
                                                            capacity: models.count)
        
        for model in models {
            modelParamsPtr.pointee.modelMatrix = model.modelMatrix
            modelParamsPtr.pointee.tiling = model.tiling
            modelParamsPtr = modelParamsPtr.advanced(by: 1)
        }
    }
}
