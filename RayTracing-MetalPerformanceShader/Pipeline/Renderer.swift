//
/**
 * Copyright (c) 2018 Razeware LLC
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
 * distribute, sublicense, create a derivative work, and/or sell copies of the
 * Software in any work that is designed, intended, or marketed for pedagogical or
 * instructional purposes related to programming, coding, application development,
 * or information technology.  Permission for such use, copying, modification,
 * merger, publication, distribution, sublicensing, creation of derivative works,
 * or sale is expressly withheld.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

import MetalKit
import MetalPerformanceShaders

class Renderer: NSObject {
    var device: MTLDevice!
    var commandQ: MTLCommandQueue!
    var library: MTLLibrary!
  
    var renderPipeline: MTLRenderPipelineState!
    var primaryRayPipeline: MTLComputePipelineState!
    var rayBouncePipeline: MTLComputePipelineState!
    var accumulatePipeline: MTLComputePipelineState!
    var rayColorPipeline: MTLComputePipelineState!
    
    var rayBuffer: MTLBuffer!
    var shadowRayBuffer: MTLBuffer!
  
    var renderTarget: MTLTexture!
    var accumTarget: MTLTexture!
    
    var accelStruct: MPSTriangleAccelerationStructure!
  
    var vertexPosBuffer: MTLBuffer!
    var vertexNormalBuffer: MTLBuffer!
    var vertexColorBuffer: MTLBuffer!
    var idxBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    var randomBuffer: MTLBuffer!
  
    var intersectionBuffer: MTLBuffer!
    let intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.stride
  
    var intersector: MPSRayIntersector!
    let rayStride = MemoryLayout<MPSRayOriginMinDistanceDirectionMaxDistance>.stride
                    + MemoryLayout<float3>.stride
  
    var size = CGSize.zero
    var frameIdx: uint = 0
    
    let randomSize = 256
  
    lazy var vertexDescriptor: MDLVertexDescriptor = {
        let desc = MDLVertexDescriptor()
        desc.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                format: .float3,
                                                offset: 0,
                                                bufferIndex: 0)
        
        desc.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                format: .float3,
                                                offset: 0,
                                                bufferIndex: 1)
        desc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<float3>.stride)
        desc.layouts[1] = MDLVertexBufferLayout(stride: MemoryLayout<float3>.stride)
        return desc
    }()
  
    var vertices: [float3] = []
    var normals: [float3] = []
    var colors: [float3] = []
  
    init(metalView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("GPU not available")
        }
    
        metalView.device = device
        metalView.colorPixelFormat = .rgba16Float
        metalView.sampleCount = 1
        metalView.drawableSize = metalView.frame.size
    
        self.device = device
        commandQ = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()
    
    
        super.init()
        metalView.delegate = self
        
        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
        
        buildPipelines(view: metalView)
        createScene()
        createBuffers()
        buildIntersector()
        buildAccelerationStructure()
    }
  
  func buildAccelerationStructure() {
      accelStruct = MPSTriangleAccelerationStructure(device: device)
      accelStruct?.vertexBuffer = vertexPosBuffer
      accelStruct?.triangleCount = vertices.count / 3
      accelStruct?.rebuild()
  }
  
  func buildIntersector() {
      intersector = MPSRayIntersector(device: device)
      intersector?.rayDataType = .originMinDistanceDirectionMaxDistance
      intersector?.rayStride = rayStride
  }
  
  func buildPipelines(view: MTKView) {
      let vertexFunc = library.makeFunction(name: "vertexShader")
      let fragmentFunc = library.makeFunction(name: "fragmentShader")
      
      let renderPipeDesc = MTLRenderPipelineDescriptor()
      renderPipeDesc.sampleCount = view.sampleCount
      renderPipeDesc.vertexFunction = vertexFunc
      renderPipeDesc.fragmentFunction = fragmentFunc
      renderPipeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
      
      let computePipeDesc = MTLComputePipelineDescriptor()
      computePipeDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
    
      do {
          renderPipeline = try device.makeRenderPipelineState(descriptor: renderPipeDesc)
          
          computePipeDesc.computeFunction = library.makeFunction(name: "primaryRays")
          primaryRayPipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                            options: [],
                                                            reflection: nil)
          
          computePipeDesc.computeFunction = library.makeFunction(name: "rayBounce")
          rayBouncePipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                              options: [],
                                                              reflection: nil)
          
          computePipeDesc.computeFunction = library.makeFunction(name: "rayColor")
          rayColorPipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                               options: [],
                                                               reflection: nil)
      
          computePipeDesc.computeFunction = library.makeFunction(name: "accumulate")
          accumulatePipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                                   options: [],
                                                                   reflection: nil)
    
      } catch {
          print(error.localizedDescription)
      }
  }
  
  func createScene() {
      loadAsset(name: "train", position: [-0.3, 0, 0.4], scale: 0.5)
      loadAsset(name: "treefir", position: [0.5, 0, -0.2], scale: 0.7)
      loadAsset(name: "plane", position: [0, 0, 0], scale: 10)
      loadAsset(name: "sphere", position: [-1.9, 0.0, 0.3], scale: 1)
      loadAsset(name: "sphere", position: [2.9, 0.0, -0.5], scale: 2)
      loadAsset(name: "plane-back", position: [0, 0, -1.5], scale: 10)
  }
  
  
  func createBuffers() {
      let options: MTLResourceOptions = {
          return .storageModeManaged
      } ()
    
      uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.stride,
                                        options: options)
      
      randomBuffer = device.makeBuffer(length: randomSize * MemoryLayout<float2>.stride,
                                       options: options)
      
      vertexPosBuffer = device.makeBuffer(bytes: &vertices,
                                               length: vertices.count * MemoryLayout<float3>.stride,
                                               options: options)
      
      vertexColorBuffer = device.makeBuffer(bytes: &colors,
                                            length: colors.count * MemoryLayout<float3>.stride,
                                            options: options)
      
      vertexNormalBuffer = device.makeBuffer(bytes: &normals,
                                             length: normals.count * MemoryLayout<float3>.stride,
                                             options: options)
  }
  
  func updateUniforms() {
      let uniforms = uniformBuffer!.contents().bindMemory(to: Uniforms.self, capacity: 1)
    
      var camera = Camera()
      camera.pos = float3(0.0, 1.0, 3.38)
      camera.forward = float3(0.0, 0.0, -1.0)
      camera.right = float3(1.0, 0.0, 0.0)
      camera.up = float3(0.0, 1.0, 0.0)
    
      let fieldOfView = 45.0 * (Float.pi / 180.0)
      let aspectRatio = Float(size.width) / Float(size.height)
      let imagePlaneHeight = tanf(fieldOfView / 2.0)
      let imagePlaneWidth = aspectRatio * imagePlaneHeight
    
      camera.right *= imagePlaneWidth
      camera.up *= imagePlaneHeight
    
      var light = AreaLight()
      light.pos = float3(0.0, 1.98, 0.0)
      light.forward = float3(0.0, -1.0, 0.0)
      light.right = float3(0.25, 0.0, 0.0)
      light.up = float3(0.0, 0.0, 0.25)
      light.color = float3(4.0, 4.0, 4.0)
    
      uniforms.pointee.camera = camera
      uniforms.pointee.light = light
    
      uniforms.pointee.width = uint(size.width)
      uniforms.pointee.height = uint(size.height)
      uniforms.pointee.frameIdx = frameIdx
        
      uniformBuffer?.didModifyRange(0..<MemoryLayout<Uniforms>.stride)
  }
  
  func updateRandomBuffer() {
      var random = randomBuffer!.contents().bindMemory(to: float2.self, capacity: randomSize)
      
      for _ in 0..<randomSize {
          random.pointee = float2(Float(drand48()), Float(drand48()) )
          random = random.advanced(by: 1)
      }
      
      randomBuffer?.didModifyRange(0..<randomSize * MemoryLayout<float2>.stride)
  }

}


extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.size = size
        frameIdx = 0
        
        let texDesc = MTLTextureDescriptor()
        texDesc.pixelFormat = .rgba32Float
        texDesc.textureType = .type2D
        texDesc.width = Int(size.width)
        texDesc.height = Int(size.height)
        texDesc.storageMode = .private
        texDesc.usage = [.shaderRead, .shaderWrite]
        
        renderTarget = device.makeTexture(descriptor: texDesc)
        accumTarget = device.makeTexture(descriptor: texDesc)
        
        let rayCount = Int(size.width * size.height)
        
        rayBuffer = device.makeBuffer(length: rayStride * rayCount,
                                      options: .storageModePrivate)
        
        shadowRayBuffer = device.makeBuffer(length: rayStride * rayCount,
                                            options: .storageModePrivate)
        
        intersectionBuffer = device.makeBuffer(length: intersectionStride * rayCount,
                                               options: .storageModePrivate)
    }
    
    func draw(in view: MTKView) {
        guard let commandBuffer = commandQ.makeCommandBuffer() else {
            return
        }
        
        frameIdx += 1
        updateUniforms()
        updateRandomBuffer()
        
        // 1 generate primary ray
        let width = Int(size.width)
        let height = Int(size.height)
        let threadsPerGroup = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake((width + threadsPerGroup.width - 1) / threadsPerGroup.width,
                                       (height + threadsPerGroup.height - 1) / threadsPerGroup.height,
                                       1)
        
        var computeEncoder = commandBuffer.makeComputeCommandEncoder()
        computeEncoder?.setComputePipelineState(primaryRayPipeline)
        computeEncoder?.label = "Generate Rays"
        computeEncoder?.setBuffer(uniformBuffer, offset: 0, index: 0) //read
        computeEncoder?.setBuffer(rayBuffer, offset: 0, index: 1) // write primary ray
        computeEncoder?.setBuffer(randomBuffer, offset: 0, index: 2) // read
        computeEncoder?.setTexture(renderTarget, index: 0) // write black
        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder?.endEncoding()
        
        let maxBouncing = 5
        
        for _ in 0..<maxBouncing {
            // 2 intersection check - rayBuffer
            intersector?.intersectionDataType = .distancePrimitiveIndexCoordinates
            intersector?.encodeIntersection(commandBuffer: commandBuffer,
                                            intersectionType: .nearest,
                                            rayBuffer: rayBuffer,
                                            rayBufferOffset: 0,
                                            intersectionBuffer: intersectionBuffer,
                                            intersectionBufferOffset: 0,
                                            rayCount: width * height,
                                            accelerationStructure: accelStruct)
            
            // 3 write next bouncing
            computeEncoder = commandBuffer.makeComputeCommandEncoder()
            computeEncoder?.setComputePipelineState(rayBouncePipeline!)
            computeEncoder?.label = "Ray Bounce"
            computeEncoder?.setBuffer(uniformBuffer, offset: 0, index: 0) // read
            computeEncoder?.setBuffer(rayBuffer, offset: 0, index: 1) // read, write
            computeEncoder?.setBuffer(shadowRayBuffer, offset: 0, index: 2) // read, write
            computeEncoder?.setBuffer(intersectionBuffer, offset: 0, index: 3) // read
            computeEncoder?.setBuffer(vertexColorBuffer, offset: 0, index: 4) // read
            computeEncoder?.setBuffer(vertexNormalBuffer, offset: 0, index: 5) // read
            computeEncoder?.setBuffer(randomBuffer, offset: 0, index: 6) // read
            computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder?.endEncoding()
            
            // 4 intersection check - shadowRayBuffer (3에서 쓰인 next ray에서 라이트소스 방향으로 가려짐이 있는지 체크)
            intersector?.label = "Shadows Intersector"
            intersector?.intersectionDataType = .distance
            intersector?.encodeIntersection(commandBuffer: commandBuffer,
                                            intersectionType: .any,
                                            rayBuffer: shadowRayBuffer,
                                            rayBufferOffset: 0,
                                            intersectionBuffer: intersectionBuffer,
                                            intersectionBufferOffset: 0,
                                            rayCount: width * height,
                                            accelerationStructure: accelStruct)
            
            // 5 add ray color to renderTarget
            computeEncoder = commandBuffer.makeComputeCommandEncoder()
            computeEncoder?.setComputePipelineState(rayColorPipeline!)
            computeEncoder?.label = "Ray Color"
            computeEncoder?.setBuffer(uniformBuffer, offset: 0, index: 0)
            computeEncoder?.setBuffer(shadowRayBuffer, offset: 0, index: 1)
            computeEncoder?.setBuffer(intersectionBuffer, offset: 0, index: 2)
            computeEncoder?.setTexture(renderTarget, index: 0)
            computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
            computeEncoder?.endEncoding()
        }
        
        // 6 average: sum(renderTarget[0:frameIndex]) / frameIndex
        computeEncoder = commandBuffer.makeComputeCommandEncoder()
        computeEncoder?.setComputePipelineState(accumulatePipeline)
        computeEncoder?.label = "Accumulation"
        computeEncoder?.setBuffer(uniformBuffer, offset: 0, index: 0)
        computeEncoder?.setTexture(renderTarget, index: 0)
        computeEncoder?.setTexture(accumTarget, index: 1)
        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
        computeEncoder?.endEncoding()
        
        // 7 render averaged color
        guard let renderDesc = view.currentRenderPassDescriptor,
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc)
        else { return }
        
        renderEncoder.setRenderPipelineState(renderPipeline!)
        renderEncoder.setFragmentTexture(accumTarget, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        renderEncoder.endEncoding()

        guard let drawable = view.currentDrawable else { return }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
