
import MetalKit

class Renderer: NSObject {
    static var device: MTLDevice!
    static var cmdQ: MTLCommandQueue!
    static var lib: MTLLibrary!
    
    var uniforms = Uniforms()
    var fragUniforms = FragmentUniforms()
    var modelParams = ModelParams()
    
    let depthStencilState: MTLDepthStencilState
    
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
    }


    static func buildDepthStencilState() -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        return Renderer.device.makeDepthStencilState(descriptor: descriptor)
    }
}


extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        camera.aspect = Float(view.bounds.width)/Float(view.bounds.height)
    }
    
    
    func draw(in view: MTKView) {
        guard
            let descriptor = view.currentRenderPassDescriptor,
            let cmdBuf = Renderer.cmdQ.makeCommandBuffer() else { return }
        
        updateUniforms()
        
        guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        
        
        encoder.setDepthStencilState(depthStencilState)
        
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, 
                               index: Int(BufferIndexUniforms.rawValue))
        
        encoder.setFragmentBytes(&fragUniforms, length: MemoryLayout<FragmentUniforms>.stride, 
                                 index: Int(BufferIndexFragmentUniforms.rawValue))
        
        
        for model in models {
            encoder.pushDebugGroup(model.name)
            
            modelParams.modelMatrix = model.modelMatrix
            modelParams.tiling = model.tiling
            
            encoder.setVertexBytes(&modelParams,
                                   length:MemoryLayout<ModelParams>.stride,
                                   index: Int(BufferIndexModelParams.rawValue))
            
            
            encoder.setFragmentBytes(&modelParams,
                                     length:MemoryLayout<ModelParams>.stride,
                                     index: Int(BufferIndexModelParams.rawValue))

            
            encoder.setRenderPipelineState(model.pipelineState)
            
            
            encoder.setVertexBuffer(model.vertexBuffer, offset: 0, index: 0)
            
            encoder.setFragmentTexture(model.colorTexture, index: Int(BaseColorTexture.rawValue))
            encoder.setFragmentTexture(model.normalTexture, index: Int(NormalTexture.rawValue))
            
            let subMesh = model.submesh
            
            encoder.drawIndexedPrimitives(type: .triangle, 
                                          indexCount: subMesh.indexCount,
                                          indexType: subMesh.indexType, 
                                          indexBuffer: subMesh.indexBuffer.buffer,
                                          indexBufferOffset: subMesh.indexBuffer.offset)
            
            encoder.popDebugGroup()
        }
        
        encoder.endEncoding()
        
        guard let drawable = view.currentDrawable else { return }
        
        cmdBuf.present(drawable)
        cmdBuf.commit()
        
    }
    
    func updateUniforms() {
        uniforms.projectionMatrix = camera.projectionMatrix
        uniforms.viewMatrix = camera.viewMatrix
        fragUniforms.cameraPosition = camera.position
    }
}
