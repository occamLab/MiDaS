// Copyright 2019 The TensorFlow Authors. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// =============================================================================

import Accelerate
import Foundation
import ARKit

extension CVPixelBuffer {
  var size: CGSize {
    return CGSize(width: CVPixelBufferGetWidth(self), height: CVPixelBufferGetHeight(self))
  }

  /// Returns a new `CVPixelBuffer` created by taking the self area and resizing it to the
  /// specified target size. Aspect ratios of source image and destination image are expected to be
  /// same.
  ///
  /// - Parameters:
  ///   - from: Source area of image to be cropped and resized.
  ///   - to: Size to scale the image to(i.e. image size used while training the model).
  /// - Returns: The cropped and resized image of itself.
  func resize(from source: CGRect, to size: CGSize) -> CVPixelBuffer? {
    let rect = CGRect(origin: CGPoint(x: 0, y: 0), size: self.size)
    guard rect.contains(source) else {
      os_log("Resizing Error: source area is out of index", type: .error)
      return nil
    }
    guard rect.size.width / rect.size.height - source.size.width / source.size.height < 1e-5
    else {
      os_log(
        "Resizing Error: source image ratio and destination image ratio is different",
        type: .error)
      return nil
    }

    let inputImageRowBytes = CVPixelBufferGetBytesPerRow(self)
    let imageChannels = 4

    CVPixelBufferLockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0))
    defer { CVPixelBufferUnlockBaseAddress(self, CVPixelBufferLockFlags(rawValue: 0)) }

    // Finds the address of the upper leftmost pixel of the source area.
    guard
      let inputBaseAddress = CVPixelBufferGetBaseAddress(self)?.advanced(
        by: Int(source.minY) * inputImageRowBytes + Int(source.minX) * imageChannels)
    else {
      return nil
    }

    // Crops given area as vImage Buffer.
    var croppedImage = vImage_Buffer(
      data: inputBaseAddress, height: UInt(source.height), width: UInt(source.width),
      rowBytes: inputImageRowBytes)

    let resultRowBytes = Int(size.width) * imageChannels
    guard let resultAddress = malloc(Int(size.height) * resultRowBytes) else {
      return nil
    }

    // Allocates a vacant vImage buffer for resized image.
    var resizedImage = vImage_Buffer(
      data: resultAddress,
      height: UInt(size.height), width: UInt(size.width),
      rowBytes: resultRowBytes
    )

    // Performs the scale operation on cropped image and stores it in result image buffer.
    guard vImageScale_ARGB8888(&croppedImage, &resizedImage, nil, vImage_Flags(0)) == kvImageNoError
    else {
      return nil
    }

    let releaseCallBack: CVPixelBufferReleaseBytesCallback = { mutablePointer, pointer in
      if let pointer = pointer {
        free(UnsafeMutableRawPointer(mutating: pointer))
      }
    }

    var result: CVPixelBuffer?

    // Converts the thumbnail vImage buffer to CVPixelBuffer
    let conversionStatus = CVPixelBufferCreateWithBytes(
      nil,
      Int(size.width), Int(size.height),
      CVPixelBufferGetPixelFormatType(self),
      resultAddress,
      resultRowBytes,
      releaseCallBack,
      nil,
      nil,
      &result
    )

    guard conversionStatus == kCVReturnSuccess else {
      free(resultAddress)
      return nil
    }

    return result
  }

  /// Returns the RGB `Data` representation of the given image buffer.
  ///
  /// - Parameters:
  ///   - isModelQuantized: Whether the model is quantized (i.e. fixed point values rather than
  ///       floating point values).
  /// - Returns: The RGB data representation of the image buffer or `nil` if the buffer could not be
  ///     converted.
  func rgbData(
    isModelQuantized: Bool
  ) -> Data? {
    CVPixelBufferLockBaseAddress(self, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(self, .readOnly) }
    guard let sourceData = CVPixelBufferGetBaseAddress(self) else {
      return nil
    }

    let width = CVPixelBufferGetWidth(self)
    let height = CVPixelBufferGetHeight(self)
    let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(self)
    let destinationBytesPerRow = Constants.rgbPixelChannels * width

    // Assign input image to `sourceBuffer` to convert it.
    var sourceBuffer = vImage_Buffer(
      data: sourceData,
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: sourceBytesPerRow)

    // Make `destinationBuffer` and `destinationData` for its data to be assigned.
    guard let destinationData = malloc(height * destinationBytesPerRow) else {
      os_log("Error: out of memory", type: .error)
      return nil
    }
    defer { free(destinationData) }
    var destinationBuffer = vImage_Buffer(
      data: destinationData,
      height: vImagePixelCount(height),
      width: vImagePixelCount(width),
      rowBytes: destinationBytesPerRow)

    // Convert image type.
    switch CVPixelBufferGetPixelFormatType(self) {
    case kCVPixelFormatType_32BGRA:
      vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    case kCVPixelFormatType_32ARGB:
      vImageConvert_BGRA8888toRGB888(&sourceBuffer, &destinationBuffer, UInt32(kvImageNoFlags))
    default:
      os_log("The type of this image is not supported.", type: .error)
      return nil
    }

    // Make `Data` with converted image.
    let imageByteData = Data(
      bytes: destinationBuffer.data, count: destinationBuffer.rowBytes * height)

    if isModelQuantized { return imageByteData }

    let imageBytes = [UInt8](imageByteData)
    return Data(copyingBufferOf: imageBytes.map { Float($0) / Constants.maxRGBValue })
  }
}


public func CVPixelBufferGetPixelFormatName(pixelBuffer: CVPixelBuffer) -> String {
    let p = CVPixelBufferGetPixelFormatType(pixelBuffer)
    switch p {
    case kCVPixelFormatType_1Monochrome:                   return "kCVPixelFormatType_1Monochrome"
    case kCVPixelFormatType_2Indexed:                      return "kCVPixelFormatType_2Indexed"
    case kCVPixelFormatType_4Indexed:                      return "kCVPixelFormatType_4Indexed"
    case kCVPixelFormatType_8Indexed:                      return "kCVPixelFormatType_8Indexed"
    case kCVPixelFormatType_1IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_1IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_2IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_2IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_4IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_4IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_8IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_8IndexedGray_WhiteIsZero"
    case kCVPixelFormatType_16BE555:                       return "kCVPixelFormatType_16BE555"
    case kCVPixelFormatType_16LE555:                       return "kCVPixelFormatType_16LE555"
    case kCVPixelFormatType_16LE5551:                      return "kCVPixelFormatType_16LE5551"
    case kCVPixelFormatType_16BE565:                       return "kCVPixelFormatType_16BE565"
    case kCVPixelFormatType_16LE565:                       return "kCVPixelFormatType_16LE565"
    case kCVPixelFormatType_24RGB:                         return "kCVPixelFormatType_24RGB"
    case kCVPixelFormatType_24BGR:                         return "kCVPixelFormatType_24BGR"
    case kCVPixelFormatType_32ARGB:                        return "kCVPixelFormatType_32ARGB"
    case kCVPixelFormatType_32BGRA:                        return "kCVPixelFormatType_32BGRA"
    case kCVPixelFormatType_32ABGR:                        return "kCVPixelFormatType_32ABGR"
    case kCVPixelFormatType_32RGBA:                        return "kCVPixelFormatType_32RGBA"
    case kCVPixelFormatType_64ARGB:                        return "kCVPixelFormatType_64ARGB"
    case kCVPixelFormatType_48RGB:                         return "kCVPixelFormatType_48RGB"
    case kCVPixelFormatType_32AlphaGray:                   return "kCVPixelFormatType_32AlphaGray"
    case kCVPixelFormatType_16Gray:                        return "kCVPixelFormatType_16Gray"
    case kCVPixelFormatType_30RGB:                         return "kCVPixelFormatType_30RGB"
    case kCVPixelFormatType_422YpCbCr8:                    return "kCVPixelFormatType_422YpCbCr8"
    case kCVPixelFormatType_4444YpCbCrA8:                  return "kCVPixelFormatType_4444YpCbCrA8"
    case kCVPixelFormatType_4444YpCbCrA8R:                 return "kCVPixelFormatType_4444YpCbCrA8R"
    case kCVPixelFormatType_4444AYpCbCr8:                  return "kCVPixelFormatType_4444AYpCbCr8"
    case kCVPixelFormatType_4444AYpCbCr16:                 return "kCVPixelFormatType_4444AYpCbCr16"
    case kCVPixelFormatType_444YpCbCr8:                    return "kCVPixelFormatType_444YpCbCr8"
    case kCVPixelFormatType_422YpCbCr16:                   return "kCVPixelFormatType_422YpCbCr16"
    case kCVPixelFormatType_422YpCbCr10:                   return "kCVPixelFormatType_422YpCbCr10"
    case kCVPixelFormatType_444YpCbCr10:                   return "kCVPixelFormatType_444YpCbCr10"
    case kCVPixelFormatType_420YpCbCr8Planar:              return "kCVPixelFormatType_420YpCbCr8Planar"
    case kCVPixelFormatType_420YpCbCr8PlanarFullRange:     return "kCVPixelFormatType_420YpCbCr8PlanarFullRange"
    case kCVPixelFormatType_422YpCbCr_4A_8BiPlanar:        return "kCVPixelFormatType_422YpCbCr_4A_8BiPlanar"
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:  return "kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange"
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:   return "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange"
    case kCVPixelFormatType_422YpCbCr8_yuvs:               return "kCVPixelFormatType_422YpCbCr8_yuvs"
    case kCVPixelFormatType_422YpCbCr8FullRange:           return "kCVPixelFormatType_422YpCbCr8FullRange"
    case kCVPixelFormatType_OneComponent8:                 return "kCVPixelFormatType_OneComponent8"
    case kCVPixelFormatType_TwoComponent8:                 return "kCVPixelFormatType_TwoComponent8"
    case kCVPixelFormatType_30RGBLEPackedWideGamut:        return "kCVPixelFormatType_30RGBLEPackedWideGamut"
    case kCVPixelFormatType_OneComponent16Half:            return "kCVPixelFormatType_OneComponent16Half"
    case kCVPixelFormatType_OneComponent32Float:           return "kCVPixelFormatType_OneComponent32Float"
    case kCVPixelFormatType_TwoComponent16Half:            return "kCVPixelFormatType_TwoComponent16Half"
    case kCVPixelFormatType_TwoComponent32Float:           return "kCVPixelFormatType_TwoComponent32Float"
    case kCVPixelFormatType_64RGBAHalf:                    return "kCVPixelFormatType_64RGBAHalf"
    case kCVPixelFormatType_128RGBAFloat:                  return "kCVPixelFormatType_128RGBAFloat"
    case kCVPixelFormatType_14Bayer_GRBG:                  return "kCVPixelFormatType_14Bayer_GRBG"
    case kCVPixelFormatType_14Bayer_RGGB:                  return "kCVPixelFormatType_14Bayer_RGGB"
    case kCVPixelFormatType_14Bayer_BGGR:                  return "kCVPixelFormatType_14Bayer_BGGR"
    case kCVPixelFormatType_14Bayer_GBRG:                  return "kCVPixelFormatType_14Bayer_GBRG"
    default: return "UNKNOWN"
    }
}

extension CVPixelBuffer {
    
    func pixelFormatName() -> String {
        let p = CVPixelBufferGetPixelFormatType(self)
        switch p {
        case kCVPixelFormatType_1Monochrome:                   return "kCVPixelFormatType_1Monochrome"
        case kCVPixelFormatType_2Indexed:                      return "kCVPixelFormatType_2Indexed"
        case kCVPixelFormatType_4Indexed:                      return "kCVPixelFormatType_4Indexed"
        case kCVPixelFormatType_8Indexed:                      return "kCVPixelFormatType_8Indexed"
        case kCVPixelFormatType_1IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_1IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_2IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_2IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_4IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_4IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_8IndexedGray_WhiteIsZero:      return "kCVPixelFormatType_8IndexedGray_WhiteIsZero"
        case kCVPixelFormatType_16BE555:                       return "kCVPixelFormatType_16BE555"
        case kCVPixelFormatType_16LE555:                       return "kCVPixelFormatType_16LE555"
        case kCVPixelFormatType_16LE5551:                      return "kCVPixelFormatType_16LE5551"
        case kCVPixelFormatType_16BE565:                       return "kCVPixelFormatType_16BE565"
        case kCVPixelFormatType_16LE565:                       return "kCVPixelFormatType_16LE565"
        case kCVPixelFormatType_24RGB:                         return "kCVPixelFormatType_24RGB"
        case kCVPixelFormatType_24BGR:                         return "kCVPixelFormatType_24BGR"
        case kCVPixelFormatType_32ARGB:                        return "kCVPixelFormatType_32ARGB"
        case kCVPixelFormatType_32BGRA:                        return "kCVPixelFormatType_32BGRA"
        case kCVPixelFormatType_32ABGR:                        return "kCVPixelFormatType_32ABGR"
        case kCVPixelFormatType_32RGBA:                        return "kCVPixelFormatType_32RGBA"
        case kCVPixelFormatType_64ARGB:                        return "kCVPixelFormatType_64ARGB"
        case kCVPixelFormatType_48RGB:                         return "kCVPixelFormatType_48RGB"
        case kCVPixelFormatType_32AlphaGray:                   return "kCVPixelFormatType_32AlphaGray"
        case kCVPixelFormatType_16Gray:                        return "kCVPixelFormatType_16Gray"
        case kCVPixelFormatType_30RGB:                         return "kCVPixelFormatType_30RGB"
        case kCVPixelFormatType_422YpCbCr8:                    return "kCVPixelFormatType_422YpCbCr8"
        case kCVPixelFormatType_4444YpCbCrA8:                  return "kCVPixelFormatType_4444YpCbCrA8"
        case kCVPixelFormatType_4444YpCbCrA8R:                 return "kCVPixelFormatType_4444YpCbCrA8R"
        case kCVPixelFormatType_4444AYpCbCr8:                  return "kCVPixelFormatType_4444AYpCbCr8"
        case kCVPixelFormatType_4444AYpCbCr16:                 return "kCVPixelFormatType_4444AYpCbCr16"
        case kCVPixelFormatType_444YpCbCr8:                    return "kCVPixelFormatType_444YpCbCr8"
        case kCVPixelFormatType_422YpCbCr16:                   return "kCVPixelFormatType_422YpCbCr16"
        case kCVPixelFormatType_422YpCbCr10:                   return "kCVPixelFormatType_422YpCbCr10"
        case kCVPixelFormatType_444YpCbCr10:                   return "kCVPixelFormatType_444YpCbCr10"
        case kCVPixelFormatType_420YpCbCr8Planar:              return "kCVPixelFormatType_420YpCbCr8Planar"
        case kCVPixelFormatType_420YpCbCr8PlanarFullRange:     return "kCVPixelFormatType_420YpCbCr8PlanarFullRange"
        case kCVPixelFormatType_422YpCbCr_4A_8BiPlanar:        return "kCVPixelFormatType_422YpCbCr_4A_8BiPlanar"
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:  return "kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange"
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:   return "kCVPixelFormatType_420YpCbCr8BiPlanarFullRange"
        case kCVPixelFormatType_422YpCbCr8_yuvs:               return "kCVPixelFormatType_422YpCbCr8_yuvs"
        case kCVPixelFormatType_422YpCbCr8FullRange:           return "kCVPixelFormatType_422YpCbCr8FullRange"
        case kCVPixelFormatType_OneComponent8:                 return "kCVPixelFormatType_OneComponent8"
        case kCVPixelFormatType_TwoComponent8:                 return "kCVPixelFormatType_TwoComponent8"
        case kCVPixelFormatType_30RGBLEPackedWideGamut:        return "kCVPixelFormatType_30RGBLEPackedWideGamut"
        case kCVPixelFormatType_OneComponent16Half:            return "kCVPixelFormatType_OneComponent16Half"
        case kCVPixelFormatType_OneComponent32Float:           return "kCVPixelFormatType_OneComponent32Float"
        case kCVPixelFormatType_TwoComponent16Half:            return "kCVPixelFormatType_TwoComponent16Half"
        case kCVPixelFormatType_TwoComponent32Float:           return "kCVPixelFormatType_TwoComponent32Float"
        case kCVPixelFormatType_64RGBAHalf:                    return "kCVPixelFormatType_64RGBAHalf"
        case kCVPixelFormatType_128RGBAFloat:                  return "kCVPixelFormatType_128RGBAFloat"
        case kCVPixelFormatType_14Bayer_GRBG:                  return "kCVPixelFormatType_14Bayer_GRBG"
        case kCVPixelFormatType_14Bayer_RGGB:                  return "kCVPixelFormatType_14Bayer_RGGB"
        case kCVPixelFormatType_14Bayer_BGGR:                  return "kCVPixelFormatType_14Bayer_BGGR"
        case kCVPixelFormatType_14Bayer_GBRG:                  return "kCVPixelFormatType_14Bayer_GBRG"
        default: return "UNKNOWN"
        }
    }
}



// Add objc is designed to allow OC to call it directly. If it is not needed, it can be removed
@objc class AECapturedTools: NSObject {
    
    @objc class func strType(from os: OSType) -> String {
        var str = ""
        str.append(String(UnicodeScalar((os >> 24) & 0xFF)!))
        str.append(String(UnicodeScalar((os >> 16) & 0xFF)!))
        str.append(String(UnicodeScalar((os >> 8) & 0xFF)!))
        str.append(String(UnicodeScalar(os & 0xFF)!))
        return str
    }
    
    @objc public var rgbPixel: CVPixelBuffer!

    @objc init(frame: ARFrame) throws {
        let pixelBuffer = frame.capturedImage

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let yDate = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)
        let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)

        var yImage = vImage_Buffer(data: yDate!, height: vImagePixelCount(yHeight), width: vImagePixelCount(yWidth), rowBytes: Int(yBytesPerRow))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let cDate = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        let cHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        let cWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1)
        let cBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        var cImage = vImage_Buffer(data: cDate!, height: vImagePixelCount(cHeight), width: vImagePixelCount(cWidth), rowBytes: Int(cBytesPerRow))
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        var outRef: CVPixelBuffer? = nil
        CVPixelBufferCreate(kCFAllocatorDefault, yWidth, yHeight, kCVPixelFormatType_32BGRA, nil, &outRef)
        CVPixelBufferLockBaseAddress(outRef!, .readOnly)
        let oDate = CVPixelBufferGetBaseAddress(outRef!)
        let oHeight = CVPixelBufferGetHeight(outRef!)
        let oWidth = CVPixelBufferGetWidth(outRef!)
        let oBytesPerRow = CVPixelBufferGetBytesPerRow(outRef!)
        CVPixelBufferUnlockBaseAddress(outRef!, .readOnly)

        var oImage = vImage_Buffer(data: oDate!, height: vImagePixelCount(oHeight), width: vImagePixelCount(oWidth), rowBytes: Int(oBytesPerRow))

        var pixelRange = vImage_YpCbCrPixelRange(Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255, YpMax: 255, YpMin: 1, CbCrMax: 255, CbCrMin: 0)
        var matrix = vImage_YpCbCrToARGB()
        vImageConvert_YpCbCrToARGB_GenerateConversion(kvImage_YpCbCrToARGBMatrix_ITU_R_709_2, &pixelRange, &matrix, kvImage420Yp8_CbCr8, kvImageARGB8888, UInt32(kvImageNoFlags))
        
        let error = vImageConvert_420Yp8_CbCr8ToARGB8888(&yImage, &cImage, &oImage, &matrix, nil, 255, UInt32(kvImageNoFlags))
        let channelMap: [UInt8] = [3, 2, 1, 0]
        vImagePermuteChannels_ARGB8888(&oImage, &oImage, channelMap, 0)
        if error != kvImageNoError {
            debugPrint(error)
        }
        rgbPixel = outRef
    }
    
    deinit {
        print("释放")
    }
}

/**
 First crops the pixel buffer, then resizes it.
 */
public func resizePixelBuffer(_ srcPixelBuffer: CVPixelBuffer,
                              cropX: Int,
                              cropY: Int,
                              cropWidth: Int,
                              cropHeight: Int,
                              scaleWidth: Int,
                              scaleHeight: Int) -> CVPixelBuffer? {
    
    CVPixelBufferLockBaseAddress(srcPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    guard let srcData = CVPixelBufferGetBaseAddress(srcPixelBuffer) else {
        print("Error: could not get pixel buffer base address")
        return nil
    }
    let srcBytesPerRow = CVPixelBufferGetBytesPerRow(srcPixelBuffer)
    let offset = cropY*srcBytesPerRow + cropX*4
    var srcBuffer = vImage_Buffer(data: srcData.advanced(by: offset),
                                  height: vImagePixelCount(cropHeight),
                                  width: vImagePixelCount(cropWidth),
                                  rowBytes: srcBytesPerRow)
    
    let destBytesPerRow = scaleWidth*4
    guard let destData = malloc(scaleHeight*destBytesPerRow) else {
        print("Error: out of memory")
        return nil
    }
    var destBuffer = vImage_Buffer(data: destData,
                                   height: vImagePixelCount(scaleHeight),
                                   width: vImagePixelCount(scaleWidth),
                                   rowBytes: destBytesPerRow)
    
    let error = vImageScale_ARGB8888(&srcBuffer, &destBuffer, nil, vImage_Flags(0))
    CVPixelBufferUnlockBaseAddress(srcPixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
    if error != kvImageNoError {
        print("Error:", error)
        free(destData)
        return nil
    }
    
    let releaseCallback: CVPixelBufferReleaseBytesCallback = { _, ptr in
        if let ptr = ptr {
            free(UnsafeMutableRawPointer(mutating: ptr))
        }
    }
    
    let pixelFormat = CVPixelBufferGetPixelFormatType(srcPixelBuffer)
    var dstPixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreateWithBytes(nil, scaleWidth, scaleHeight,
                                              pixelFormat, destData,
                                              destBytesPerRow, releaseCallback,
                                              nil, nil, &dstPixelBuffer)
    if status != kCVReturnSuccess {
        print("Error: could not create new pixel buffer")
        free(destData)
        return nil
    }
    return dstPixelBuffer
}
