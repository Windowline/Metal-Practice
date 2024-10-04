///**
// * Copyright (c) 2018 Razeware LLC
// *
// * Permission is hereby granted, free of charge, to any person obtaining a copy
// * of this software and associated documentation files (the "Software"), to deal
// * in the Software without restriction, including without limitation the rights
// * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// * copies of the Software, and to permit persons to whom the Software is
// * furnished to do so, subject to the following conditions:
// *
// * The above copyright notice and this permission notice shall be included in
// * all copies or substantial portions of the Software.
// *
// * Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
// * distribute, sublicense, create a derivative work, and/or sell copies of the
// * Software in any work that is designed, intended, or marketed for pedagogical or
// * instructional purposes related to programming, coding, application development,
// * or information technology.  Permission for such use, copying, modification,
// * merger, publication, distribution, sublicensing, creation of derivative works,
// * or sale is expressly withheld.
// *
// * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// * THE SOFTWARE.
// */
//
//
//import MetalKit
//import MetalPerformanceShaders
//
////typealias float2 = SIMD2<Float>
////typealias float3 = SIMD3<Float>
//
//class Renderer: NSObject {
//    var device: MTLDevice!
//    var cmdQ: MTLCommandQueue!
//    var lib: MTLLibrary!
//    
//    var rayBuf: MTLBuffer!
//    var shadowRayBuf: MTLBuffer!
//    
//    var vtxPosBuf: MTLBuffer!
//    var vtxNormBuf: MTLBuffer!
//    var vtxColorBuf: MTLBuffer!
//    var idxBuf: MTLBuffer!
//    var uniformBuf: MTLBuffer!
//    var randBuf: MTLBuffer!
//    
//    var intersectionBuf: MTLBuffer!
//    let intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.stride
//    
//    var intersector: MPSRayIntersector!
//    
//    let rayStride = MemoryLayout<MPSRayOriginMinDistanceDirectionMaxDistance>.stride
//                    + MemoryLayout<float3>.stride
//    
//    let maxFrameInFlight = 3
//    let alignedUniformSize = (MemoryLayout<Uniforms>.size + 255) & ~255
//    
//    var semaphore: DispatchSemaphore!
//    
//    var size = CGSize.zero
//    var randBufOffset = 0
//    var uniformBufOffset = 0
//    var uniformBufIdx = 0
//    var frameIdx: uint = 0
//    
//    var renderTargetTex: MTLTexture!
//    
//    var accumTargetTex: MTLTexture!
//    var accelStruct: MPSTriangleAccelerationStructure!
//    
//    var accumPS: MTLComputePipelineState!
//    var renderPS: MTLRenderPipelineState!
//    var rayPS: MTLComputePipelineState!
//    var shadePS: MTLComputePipelineState!
//    var shadowPS: MTLComputePipelineState!
//    
//    lazy var vtxDesc: MDLVertexDescriptor = {
//        let vtxDesc = MDLVertexDescriptor()
//        
//        vtxDesc.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
//                                                   format: .float3,
//                                                   offset: 0,
//                                                   bufferIndex: 0)
//        
//        vtxDesc.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
//                                                   format: .float3,
//                                                   offset: 0,
//                                                   bufferIndex: 1)
//        
//        vtxDesc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<float3>.stride)
//        vtxDesc.layouts[1] = MDLVertexBufferLayout(stride: MemoryLayout<float3>.stride)
//
//        return vtxDesc
//    }()
//    
//    var vertices: [float3] = []
//    var normals: [float3] = []
//    var colors: [float3] = []
//    
//    init(metalView: MTKView) {
//        guard let device = MTLCreateSystemDefaultDevice() else {
//            fatalError("GPU not available")
//        }
//        
//        metalView.device = device
//        metalView.colorPixelFormat = .rgba16Float
//        metalView.sampleCount = 1
//        metalView.drawableSize = metalView.frame.size
//        
//        self.device = device
//        cmdQ = device.makeCommandQueue()!
//        lib = device.makeDefaultLibrary()
//        
//        super.init()
//        
//        metalView.delegate = self
//        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
//        
//        semaphore = DispatchSemaphore.init(value: maxFrameInFlight)
//        
//        buildPipelines(view: metalView)
//        loadAssets()
//        createBuffers()
//        buildIntersector()
//        buildAccelerationStructure()
//    }
//    
//    func buildPipelines(view: MTKView) {
//        let renderPipeDesc = MTLRenderPipelineDescriptor()
//        renderPipeDesc.sampleCount = view.sampleCount
//        renderPipeDesc.vertexFunction = lib.makeFunction(name: "vertexShader")
//        renderPipeDesc.fragmentFunction = lib.makeFunction(name: "fragmentShader")
//        renderPipeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
//        
//        let computePipeDesc = MTLComputePipelineDescriptor()
//        computePipeDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
//        do {
//            //render
//            renderPS = try device.makeRenderPipelineState(descriptor: renderPipeDesc)
//            
//            // shadowKernel
//            computePipeDesc.computeFunction = lib.makeFunction(name: "shadowKernel")
//            shadowPS = try device.makeComputePipelineState(descriptor: computePipeDesc,
//                                                           options: [],
//                                                           reflection: nil)
//            
//            //shadeKernel
//            computePipeDesc.computeFunction = lib.makeFunction(name: "shadeKernel")
//            shadePS = try device.makeComputePipelineState(descriptor: computePipeDesc,
//                                                          options: [],
//                                                          reflection: nil)
//            
//            // accumulateKernel
//            computePipeDesc.computeFunction = lib.makeFunction(name: "accumulateKernel")
//            accumPS = try device.makeComputePipelineState(descriptor: computePipeDesc,
//                                                          options: [],
//                                                          reflection: nil)
//            
//            // primaryRays
//            computePipeDesc.computeFunction = lib.makeFunction(name: "primaryRays")
//            rayPS = try device.makeComputePipelineState(descriptor: computePipeDesc,
//                                                        options: [],
//                                                        reflection: nil)
//            
//        } catch {
//            print(error.localizedDescription)
//        }
//    }
//    
//    func loadAssets() {
//        loadAsset(name: "train", position: [-0.3, 0, 0.4], scale: 0.5)
//        loadAsset(name: "treefir", position: [0.5, 0, -0.2], scale: 0.7)
//        loadAsset(name: "plane", position: [0, 0, 0], scale: 10)
//        loadAsset(name: "sphere", position: [-1.9, 0.0, 0.3], scale: 1)
//        loadAsset(name: "sphere", position: [2.9, 0.0, -0.5], scale: 2)
//        loadAsset(name: "plane-back", position: [0, 0, -1.5], scale: 10)
//    }
//    
//    func createBuffers() {
//        let uniformBufSize = alignedUniformSize * maxFrameInFlight
//        let options: MTLResourceOptions = {
//          return .storageModeManaged
//        } ()
//        
//        uniformBuf = device.makeBuffer(length: uniformBufSize, 
//                                       options: options)
//        
//        randBuf = device.makeBuffer(length: 256 * MemoryLayout<float2>.stride * maxFrameInFlight,
//                                    options: options)
//        
//        vtxPosBuf = device.makeBuffer(bytes: &vertices,
//                                      length: vertices.count * MemoryLayout<float3>.stride,
//                                      options: options)
//        
//        vtxColorBuf = device.makeBuffer(bytes: &colors,
//                                        length: colors.count * MemoryLayout<float3>.stride,
//                                        options: options)
//        
//        vtxNormBuf = device.makeBuffer(bytes: &normals,
//                                       length: normals.count * MemoryLayout<float3>.stride,
//                                       options: options)
//    }
//    
//    func buildIntersector() {
//        intersector = MPSRayIntersector(device: device)
//        intersector?.rayDataType = .originMinDistanceDirectionMaxDistance
//        intersector?.rayStride = rayStride
//    }
//    
//    func buildAccelerationStructure() {
//        accelStruct = MPSTriangleAccelerationStructure(device: device)
//        accelStruct?.vertexBuffer = vtxPosBuf
//        accelStruct?.triangleCount = vertices.count / 3
//        accelStruct?.rebuild()
//    }
//}
//
//extension Renderer: MTKViewDelegate {
//    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
//        self.size = size
//        frameIdx = 0
//        
//        let renderTargetDesc = MTLTextureDescriptor()
//        renderTargetDesc.pixelFormat = .rgba32Float
//        renderTargetDesc.textureType = .type2D
//        renderTargetDesc.width = Int(size.width)
//        renderTargetDesc.height = Int(size.height)
//        renderTargetDesc.storageMode = .private
//        renderTargetDesc.usage = [.shaderRead, .shaderWrite]
//        
//        renderTargetTex = device.makeTexture(descriptor: renderTargetDesc)
//        accumTargetTex = device.makeTexture(descriptor: renderTargetDesc)
//        
//        let rayCount = Int(size.width * size.height)
//        
//        rayBuf = device.makeBuffer(length: rayStride * rayCount,
//                                   options: .storageModePrivate)
//        
//        shadowRayBuf = device.makeBuffer(length: rayStride * rayCount,
//                                        options: .storageModePrivate)
//        
//        intersectionBuf = device.makeBuffer(length: intersectionStride * rayCount,
//                                            options: .storageModePrivate)
//        
//    }
//
//    func draw(in view: MTKView) {
//        semaphore.wait()
//        guard let cmdBuf = cmdQ.makeCommandBuffer() else { return }
//        
//        cmdBuf.addCompletedHandler { cb in
//            self.semaphore.signal()
//        }
//        
//        update()
//        
////        print(uniformBuf)
//        
//        // MARK: generate primary rays
//        let width = Int(size.width)
//        let height = Int(size.height)
//        let threadsPerGroup = MTLSizeMake(8, 8, 1)
//        let threadGroups = MTLSizeMake((width + threadsPerGroup.width - 1) / threadsPerGroup.width,
//                                       (height + threadsPerGroup.height - 1) / threadsPerGroup.height,
//                                       1)
//        
//        var computeEncoder = cmdBuf.makeComputeCommandEncoder()
//        computeEncoder?.label = "Generate Primary Rays"
//        computeEncoder?.setComputePipelineState(rayPS!)
//        computeEncoder?.setBuffer(uniformBuf, offset: uniformBufOffset, index: 0)
//        computeEncoder?.setBuffer(shadowRayBuf, offset: 0, index: 1)
//        computeEncoder?.setBuffer(intersectionBuf, offset: 0, index: 2)
//        computeEncoder?.setTexture(renderTargetTex, index: 0)
//        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
//        computeEncoder?.endEncoding()
//        
//        // MARK: shading/shadow 반복
//        for _ in 0..<1 {
//            // MARK: generate intersections between rays and model triangles
//            intersector?.intersectionDataType = .distancePrimitiveIndexCoordinates
//            intersector?.encodeIntersection(
//                commandBuffer: cmdBuf,
//                intersectionType: .nearest,
//                rayBuffer: rayBuf,
//                rayBufferOffset: 0,
//                intersectionBuffer: intersectionBuf,
//                intersectionBufferOffset: 0,
//                rayCount: width * height,
//                accelerationStructure: accelStruct)
//            
//            // MARK: shading
//            computeEncoder = cmdBuf.makeComputeCommandEncoder()
//            computeEncoder?.label = "Shading"
//            computeEncoder?.setComputePipelineState(shadePS)
//            computeEncoder?.setBuffer(uniformBuf, offset: uniformBufOffset, index: 0)
//            computeEncoder?.setBuffer(rayBuf, offset: 0, index: 1)
//            computeEncoder?.setBuffer(shadowRayBuf, offset: 0, index: 2)
//            computeEncoder?.setBuffer(intersectionBuf, offset: 0, index: 3)
//            computeEncoder?.setBuffer(vtxColorBuf, offset: 0, index: 4)
//            computeEncoder?.setBuffer(vtxNormBuf, offset: 0, index: 5)
//            computeEncoder?.setBuffer(randBuf, offset: randBufOffset, index: 6)
//            computeEncoder?.setTexture(renderTargetTex, index: 0)
//            computeEncoder?.dispatchThreads(threadGroups, threadsPerThreadgroup: threadsPerGroup)
//            computeEncoder?.endEncoding()
//            
//            // MARK: shadows
//            intersector?.label = "Shadows Intersector"
//            intersector?.intersectionDataType = .distance
//            intersector?.encodeIntersection(commandBuffer: cmdBuf,
//                                            intersectionType: .any,
//                                            rayBuffer: rayBuf,
//                                            rayBufferOffset: 0,
//                                            intersectionBuffer: intersectionBuf,
//                                            intersectionBufferOffset: 0,
//                                            rayCount: width * height,
//                                            accelerationStructure: accelStruct)
//            
//            computeEncoder = cmdBuf.makeComputeCommandEncoder()
//            computeEncoder?.label = "Shadows"
//            computeEncoder?.setComputePipelineState(shadowPS!)
//            computeEncoder?.setBuffer(uniformBuf, offset: uniformBufOffset, index: 0)
//            computeEncoder?.setBuffer(shadowRayBuf, offset: 0, index: 1)
//            computeEncoder?.setBuffer(intersectionBuf, offset: 0, index: 2)
//            computeEncoder?.setTexture(renderTargetTex, index: 0)
//            computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
//            computeEncoder?.endEncoding()
//        }
//        
//        // MARK: accumulation
//        computeEncoder = cmdBuf.makeComputeCommandEncoder()
//        computeEncoder?.setComputePipelineState(accumPS)
//        computeEncoder?.label = "accumulation"
//        computeEncoder?.setBuffer(uniformBuf, offset: uniformBufOffset, index: 0)
//        computeEncoder?.setTexture(renderTargetTex, index: 0)
//        computeEncoder?.setTexture(accumTargetTex, index: 1)
//        computeEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerGroup)
//        computeEncoder?.endEncoding()
//        
//        // MARK: draw call
//        guard
//            let renderDesc = view.currentRenderPassDescriptor,
//            let renderEncoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderDesc) else {
//                return
//            }
//        
//        renderEncoder.setRenderPipelineState(renderPS)
//        renderEncoder.setFragmentTexture(accumTargetTex, index: 0)
//        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
//        renderEncoder.endEncoding()
//        
//        guard let drawable = view.currentDrawable else { return }
//        cmdBuf.present(drawable)
//        cmdBuf.commit()
//    }
//    
//    func update() {
//        updateUniforms()
//        updateRandomBuffer()
//        uniformBufIdx = (uniformBufIdx + 1) % maxFrameInFlight
//    }
//    
//    func updateUniforms() {
//        uniformBufOffset = alignedUniformSize * uniformBufIdx
//        let pointer = uniformBuf.contents().advanced(by: uniformBufOffset)
//        let uniforms = pointer.bindMemory(to: Uniforms.self, capacity: 1)
//      
//        var camera = Camera()
//        camera.pos = float3(0.0, 1.0, 3.38)
//        camera.forward = float3(0.0, 0.0, -1.0)
//        camera.right = float3(1.0, 0.0, 0.0)
//        camera.up = float3(0.0, 1.0, 0.0)
//      
//        let fieldOfView = 45.0 * (Float.pi / 180.0)
//        let aspectRatio = Float(size.width) / Float(size.height)
//        let imageHeight = tanf(fieldOfView / 2.0)
//        let imageWidth = aspectRatio * imageHeight
//      
//        camera.right *= imageWidth
//        camera.up *= imageHeight
//      
//        var light = AreaLight()
//        light.pos = float3(0.0, 1.98, 0.0)
//        light.forward = float3(0.0, -1.0, 0.0)
//        light.right = float3(0.25, 0.0, 0.0)
//        light.up = float3(0.0, 0.0, 0.25)
//        light.color = float3(4.0, 4.0, 4.0)
//      
//        uniforms.pointee.camera = camera
//        uniforms.pointee.light = light
//      
//        uniforms.pointee.width = uint(size.width)
//        uniforms.pointee.height = uint(size.height)
//        uniforms.pointee.blocksWide = ((uniforms.pointee.width) + 15) / 16
//        uniforms.pointee.frameIdx = frameIdx
//        
//        frameIdx += 1
//       
//        uniformBuf?.didModifyRange(uniformBufOffset..<(uniformBufOffset + alignedUniformSize))
//    }
//    
//    func updateRandomBuffer() {
//        randBufOffset = 256 * MemoryLayout<float2>.stride * uniformBufIdx
//        let pointer = randBuf!.contents().advanced(by: randBufOffset)
//        var random = pointer.bindMemory(to: float2.self, capacity: 256)
//        
//        for _ in 0..<256 {
//            random.pointee = float2(Float(drand48()), Float(drand48()) )
//            random = random.advanced(by: 1)
//        }
//      
//        randBuf?.didModifyRange(randBufOffset..<(randBufOffset + 256 * MemoryLayout<float2>.stride))
//    }
//    
//}
//
//


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
    var commandQueue: MTLCommandQueue!
    var library: MTLLibrary!
  
    var renderPipeline: MTLRenderPipelineState!
    var rayPipeline: MTLComputePipelineState!
    var shadePipeline: MTLComputePipelineState!
    var accumulatePipeline: MTLComputePipelineState!
    var shadowPipeline: MTLComputePipelineState!
    
    var rayBuffer: MTLBuffer!
    var shadowRayBuffer: MTLBuffer!
  
    var renderTarget: MTLTexture!
    var accumTarget: MTLTexture!
    
    var accelStruct: MPSTriangleAccelerationStructure!
  
    var vertexPositionBuffer: MTLBuffer!
    var vertexNormalBuffer: MTLBuffer!
    var vertexColorBuffer: MTLBuffer!
    var indexBuffer: MTLBuffer!
    var uniformBuffer: MTLBuffer!
    var randomBuffer: MTLBuffer!
  
    var intersectionBuffer: MTLBuffer!
    let intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.stride
  
    var intersector: MPSRayIntersector!
    let rayStride = MemoryLayout<MPSRayOriginMinDistanceDirectionMaxDistance>.stride
                    + MemoryLayout<float3>.stride
  
    let maxFramesInFlight = 3
    let alignedUniformsSize = (MemoryLayout<Uniforms>.size + 255) & ~255
    
    var semaphore: DispatchSemaphore!
    var size = CGSize.zero
    
    var randomBufferOffset = 0
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    var frameIndex: uint = 0
  
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
        commandQueue = device.makeCommandQueue()!
        library = device.makeDefaultLibrary()
    
    
        super.init()
        metalView.delegate = self
        
        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
        
        semaphore = DispatchSemaphore.init(value: maxFramesInFlight)
        
        buildPipelines(view: metalView)
        createScene()
        createBuffers()
        buildIntersector()
        buildAccelerationStructure()
    }
  
  func buildAccelerationStructure() {
      accelStruct = MPSTriangleAccelerationStructure(device: device)
      accelStruct?.vertexBuffer = vertexPositionBuffer
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
          
          computePipeDesc.computeFunction = library.makeFunction(name: "shadowKernel")
          shadowPipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                               options: [],
                                                               reflection: nil)
      
          computePipeDesc.computeFunction = library.makeFunction(name: "shadeKernel")
          shadePipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                              options: [],
                                                              reflection: nil)
      
          computePipeDesc.computeFunction = library.makeFunction(name: "accumulateKernel")
          accumulatePipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                                   options: [],
                                                                   reflection: nil)
      
          computePipeDesc.computeFunction = library.makeFunction(name: "primaryRays")
          rayPipeline = try device.makeComputePipelineState(descriptor: computePipeDesc,
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
      let uniformBufferSize = alignedUniformsSize * maxFramesInFlight

      let options: MTLResourceOptions = {
          return .storageModeManaged
      } ()
    
      uniformBuffer = device.makeBuffer(length: uniformBufferSize,
                                        options: options)
      
      randomBuffer = device.makeBuffer(length: 256 * MemoryLayout<float2>.stride * maxFramesInFlight,
                                       options: options)
      
      vertexPositionBuffer = device.makeBuffer(bytes: &vertices,
                                               length: vertices.count * MemoryLayout<float3>.stride,
                                               options: options)
      
      vertexColorBuffer = device.makeBuffer(bytes: &colors,
                                            length: colors.count * MemoryLayout<float3>.stride,
                                            options: options)
      
      vertexNormalBuffer = device.makeBuffer(bytes: &normals,
                                             length: normals.count * MemoryLayout<float3>.stride,
                                             options: options)
  }
  
  func update() {
      updateUniforms()
      updateRandomBuffer()
      uniformBufferIndex = (uniformBufferIndex + 1) % maxFramesInFlight
  }
  
  func updateUniforms() {
      uniformBufferOffset = alignedUniformsSize * uniformBufferIndex
      let pointer = uniformBuffer!.contents().advanced(by: uniformBufferOffset)
      let uniforms = pointer.bindMemory(to: Uniforms.self, capacity: 1)
    
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
      uniforms.pointee.blocksWide = ((uniforms.pointee.width) + 15) / 16
      uniforms.pointee.frameIdx = frameIndex
      frameIndex += 1
        
      uniformBuffer?.didModifyRange(uniformBufferOffset..<(uniformBufferOffset + alignedUniformsSize))
  }
  
  func updateRandomBuffer() {
      randomBufferOffset = 256 * MemoryLayout<float2>.stride * uniformBufferIndex
      let pointer = randomBuffer!.contents().advanced(by: randomBufferOffset)
      var random = pointer.bindMemory(to: float2.self, capacity: 256)
      
      for _ in 0..<256 {
          random.pointee = float2(Float(drand48()), Float(drand48()) )
          random = random.advanced(by: 1)
      }
    
      randomBuffer?.didModifyRange(randomBufferOffset..<(randomBufferOffset + 256 * MemoryLayout<float2>.stride))
  }

}


extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.size = size
        frameIndex = 0
        
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
        semaphore.wait()
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        commandBuffer.addCompletedHandler { cb in
            self.semaphore.signal()
        }
        
        update()
        
        // 1 generate primary ray
        let width = Int(size.width)
        let height = Int(size.height)
        let threadsPerGroup = MTLSizeMake(8, 8, 1)
        let threadGroups = MTLSizeMake((width + threadsPerGroup.width - 1) / threadsPerGroup.width,
                                       (height + threadsPerGroup.height - 1) / threadsPerGroup.height,
                                       1)
        
        var computeEncoder = commandBuffer.makeComputeCommandEncoder()
        computeEncoder?.setComputePipelineState(rayPipeline)
        computeEncoder?.label = "Generate Rays"
        computeEncoder?.setBuffer(uniformBuffer, offset: uniformBufferOffset, index: 0) //read
        computeEncoder?.setBuffer(rayBuffer, offset: 0, index: 1) // write primary ray
        computeEncoder?.setBuffer(randomBuffer, offset: randomBufferOffset, index: 2) // read
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
            computeEncoder?.setComputePipelineState(shadePipeline!)
            computeEncoder?.label = "Shading"
            computeEncoder?.setBuffer(uniformBuffer, offset: uniformBufferOffset, index: 0) // read
            computeEncoder?.setBuffer(rayBuffer, offset: 0, index: 1) // read, write
            computeEncoder?.setBuffer(shadowRayBuffer, offset: 0, index: 2) // read, write
            computeEncoder?.setBuffer(intersectionBuffer, offset: 0, index: 3) // read
            computeEncoder?.setBuffer(vertexColorBuffer, offset: 0, index: 4) // read
            computeEncoder?.setBuffer(vertexNormalBuffer, offset: 0, index: 5) // read
            computeEncoder?.setBuffer(randomBuffer, offset: randomBufferOffset, index: 6) // read
            computeEncoder?.setTexture(renderTarget, index: 0) // not using
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
            computeEncoder?.setComputePipelineState(shadowPipeline!)
            computeEncoder?.label = "Shadows"
            computeEncoder?.setBuffer(uniformBuffer, offset: uniformBufferOffset, index: 0)
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
        computeEncoder?.setBuffer(uniformBuffer, offset: uniformBufferOffset, index: 0)
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
