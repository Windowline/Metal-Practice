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

//typealias float2 = SIMD2<Float>
//typealias float3 = SIMD3<Float>

class Renderer: NSObject {
    var device: MTLDevice!
    var cmdQ: MTLCommandQueue!
    var lib: MTLLibrary!
    
    var rayBuf: MTLBuffer!
    var shadowRayBuf: MTLBuffer!
    
    var vtxPosBuf: MTLBuffer!
    var vtxNormBuf: MTLBuffer!
    var vtxColorBuf: MTLBuffer!
    var idxBuf: MTLBuffer!
    var uniformBuf: MTLBuffer!
    var randBuf: MTLBuffer!
    
    var intersectionBuf: MTLBuffer!
    let intersectionStride = MemoryLayout<MPSIntersectionDistancePrimitiveIndexCoordinates>.stride
    
    var intersector: MPSRayIntersector!
    
    let rayStride = MemoryLayout<MPSRayOriginMinDistanceDirectionMaxDistance>.stride
                    + MemoryLayout<float3>.stride
    
    let maxFrameInFlight = 3
    let alignedUniformSize = (MemoryLayout<Uniforms>.size + 255) & ~255
    
    var semaphore: DispatchSemaphore!
    
    var size = CGSize.zero
    var randBufOffset = 0
    var uniformBufOffset = 0
    var uniformBufIdx = 0
    var frameIdx: uint = 0
    
    var renderTargetTex: MTLTexture!
    
    var accumTargetTex: MTLTexture!
    var accelStruct: MPSTriangleAccelerationStructure!
    
    var accumPS: MTLComputePipelineState!
    var renderPS: MTLRenderPipelineState!
    var rayPS: MTLComputePipelineState!
    var shadePS: MTLComputePipelineState!
    var shadowPS: MTLComputePipelineState!
    
    lazy var vtxDesc: MDLVertexDescriptor = {
        let vtxDesc = MDLVertexDescriptor()
        
        vtxDesc.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition,
                                                   format: .float3,
                                                   offset: 0,
                                                   bufferIndex: 0)
        
        vtxDesc.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal,
                                                   format: .float2,
//                                                   format: .float3
                                                   offset: 0,
                                                   bufferIndex: 0)
        
        vtxDesc.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<float3>.stride)
        vtxDesc.layouts[1] = MDLVertexBufferLayout(stride: MemoryLayout<float3>.stride)
        return vtxDesc
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
        cmdQ = device.makeCommandQueue()!
        lib = device.makeDefaultLibrary()
        
        super.init()
        
        metalView.delegate = self
        mtkView(metalView, drawableSizeWillChange: metalView.bounds.size)
        
        semaphore = DispatchSemaphore.init(value: maxFrameInFlight)
        
        buildPipelines(view: metalView)
        loadAssets()
        createBuffers()
        buildIntersector()
        buildAccelerationStructure()
    }
    
    func buildPipelines(view: MTKView) {
        let renderPipeDesc = MTLRenderPipelineDescriptor()
        renderPipeDesc.sampleCount = view.sampleCount
        renderPipeDesc.vertexFunction = lib.makeFunction(name: "vertexShader")
        renderPipeDesc.fragmentFunction = lib.makeFunction(name: "fragmentShader")
        renderPipeDesc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
        let computePipeDesc = MTLComputePipelineDescriptor()
        computePipeDesc.threadGroupSizeIsMultipleOfThreadExecutionWidth = true
        do {
            // shadeKernel
            computePipeDesc.computeFunction = lib.makeFunction(name: "shadowKernel")
            shadowPS = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                           options: [],
                                                           reflection: nil)
            
            // accumulateKernel
            computePipeDesc.computeFunction = lib.makeFunction(name: "accumulateKernel")
            accumPS = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                          options: [],
                                                          reflection: nil)
            
            // primaryRays
            computePipeDesc.computeFunction = lib.makeFunction(name: "primaryRays")
            rayPS = try device.makeComputePipelineState(descriptor: computePipeDesc,
                                                        options: [],
                                                        reflection: nil)
            
        } catch {
            print(error.localizedDescription)
        }
    }
    
    func loadAssets() {
        loadAsset(name: "train", position: [-0.3, 0, 0.4], scale: 0.5)
        loadAsset(name: "treefir", position: [0.5, 0, -0.2], scale: 0.7)
        loadAsset(name: "plane", position: [0, 0, 0], scale: 10)
        loadAsset(name: "sphere", position: [-1.9, 0.0, 0.3], scale: 1)
        loadAsset(name: "sphere", position: [2.9, 0.0, -0.5], scale: 2)
        loadAsset(name: "plane-back", position: [0, 0, -1.5], scale: 10)
    }
    
    func createBuffers() {
        let uniformBufSize = alignedUniformSize * maxFrameInFlight
        let options: MTLResourceOptions = {
          return .storageModeManaged
        } ()
        
        uniformBuf = device.makeBuffer(length: uniformBufSize, 
                                       options: options)
        
        randBuf = device.makeBuffer(length: 256 * MemoryLayout<float2>.stride * maxFrameInFlight,
                                    options: options)
        
        vtxPosBuf = device.makeBuffer(bytes: &vertices,
                                      length: vertices.count * MemoryLayout<float3>.stride,
                                      options: options)
        
        vtxColorBuf = device.makeBuffer(bytes: &colors,
                                        length: colors.count * MemoryLayout<float3>.stride,
                                        options: options)
        
        vtxNormBuf = device.makeBuffer(bytes: &normals,
                                       length: normals.count * MemoryLayout<float3>.stride,
                                       options: options)
    }
    
    func buildIntersector() {
        intersector = MPSRayIntersector(device: device)
        intersector?.rayDataType = .originMinDistanceDirectionMaxDistance
        intersector?.rayStride = rayStride
    }
    
    func buildAccelerationStructure() {
        accelStruct = MPSTriangleAccelerationStructure(device: device)
        accelStruct?.vertexBuffer = vtxPosBuf
        accelStruct?.triangleCount = vertices.count / 3
        accelStruct?.rebuild()
    }
}

extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        self.size = size
        frameIdx = 0
        
        let renderTargetDesc = MTLTextureDescriptor()
        renderTargetDesc.pixelFormat = .rgba32Float
        renderTargetDesc.textureType = .type2D
        renderTargetDesc.width = Int(size.width)
        renderTargetDesc.height = Int(size.height)
        renderTargetDesc.storageMode = .private
        renderTargetDesc.usage = [.shaderRead, .shaderWrite]
        
        renderTargetTex = device.makeTexture(descriptor: renderTargetDesc)
        accumTargetTex = device.makeTexture(descriptor: renderTargetDesc)
        
        let rayCount = Int(size.width * size.height)
        
        rayBuf = device.makeBuffer(length: rayStride * rayCount,
                                   options: .storageModePrivate)
        
        shadowRayBuf = device.makeBuffer(length: rayStride * rayCount,
                                        options: .storageModePrivate)
        
        intersectionBuf = device.makeBuffer(length: intersectionStride * rayCount,
                                            options: .storageModePrivate)
        
    }

    func draw(in view: MTKView) {
    }
    
}


