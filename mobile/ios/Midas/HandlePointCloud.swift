//
//  HandlePointCloud.swift
//  Midas
//
//  Created by occamlab on 7/20/22.
//

import AVFoundation
import ARKit
import ARDataLogger
import MetricKit

func getTrueLidarPointCloud(logFrame: ARFrameDataLog, planes: [ARPlaneAnchor]) -> [simd_float3] {
    let depthData = logFrame.depthData
    let confidence = logFrame.confData
    var highConfidenceData : [simd_float3] = []
    let threeDPoints = depthData.map({ point in point.w * simd_float3(point.x, point.y, point.z) })
    var isPointCloseToPlane: [Bool] = Array(repeating: false, count: threeDPoints.count)
    
    for plane in planes {
        if plane.classification.description == "other"{
            let cameraToPlaneTransform =  plane.transform.inverse * logFrame.pose
            let pointCloudInPlane = threeDPoints.map({ threeDPoint in cameraToPlaneTransform * simd_float4(threeDPoint, 1.0) })
            for (idx, p) in pointCloudInPlane.enumerated() {
                if abs(p.y) < 0.2, p.x >= plane.center.x - plane.extent.x/2, p.x <= plane.center.x + plane.extent.x/2, p.z >= plane.center.z - plane.extent.z/2, p.z <= plane.center.z + plane.extent.z/2 {
                    isPointCloseToPlane[idx] = true
                }
            }
        }
    }
    
    for (idx, threeDPoint) in threeDPoints.enumerated() {
        if confidence[idx].rawValue == 2 && !isPointCloseToPlane[idx] {
            highConfidenceData.append(threeDPoint)
        }
    }
    print("highConfidenceData.count \(highConfidenceData.count)")
    if highConfidenceData.count < 0 {
        print("[")
        for p in highConfidenceData {
            print("[\(p.x), \(p.y), \(p.z)]")
        }
        print("]")
        print("hello")
    }
    return highConfidenceData
}

func getGlobalPointCloud(logFrame: ARFrameDataLog, truePointCloud: [simd_float3]) -> [simd_float3] {
    let pose = logFrame.pose
    let globalPointCloud = truePointCloud.map({ point in pose * simd_float4(point, 0.0) })
    let theta = atan2(pose[0][2], pose[2][2])
    let yAxis = simd_float3(0, 1, 0)
    let rotationMatrix = float4x4(simd_quatf(angle: -theta, axis: yAxis))
    let yawAdjustedPointCloud = globalPointCloud.map({ point in rotationMatrix * point })
    return yawAdjustedPointCloud.map({point in simd_float3(point[0], point[1], point[2])})
}

func isolateObstacles(logFrame: ARFrameDataLog, yawAdjustedPointCloud: [simd_float3]) -> [simd_float3] {
    var filteredPointCloud = yawAdjustedPointCloud.filter{$0[2] >= -4}
    let yOffset = filteredPointCloud.map({point in point[1]}).min()
    filteredPointCloud = filteredPointCloud.map({ point in simd_float3(point[0], point[1] - (yOffset ?? 0), point[2])})
    filteredPointCloud = filteredPointCloud.filter{abs($0[0]) <= 0.5}
    return filteredPointCloud
}

func findObstacles(filteredPointCloud: [simd_float3]) -> [Float] {
    let zValues = filteredPointCloud.map({ point in point[2]})
    // TODO: convert binLeftEdges to meters (use Float)
    let minZValue = Float(0)
    let maxZValue = Float(-4)
    let stepSize = Float(-0.1)
    let binLeftEdges = Array(stride(from: minZValue, through: maxZValue, by: stepSize))
    var hist: [Int] = [0]
    for binEdge in binLeftEdges {
        let leftEdge = binEdge
        let rightEdge = binEdge + stepSize  // TODO: get rid of this magic number using a linspace approach
        let filteredZValues = zValues.filter({z in z <= leftEdge && z > rightEdge})
        let numberInBin = filteredZValues.count
        hist.append(numberInBin)
    }
    var localMaxes : [Float] = []
    for i in 1..<binLeftEdges.count-1 {
        let leftCount = hist[i-1]
        let centerCount = hist[i]
        let rightCount = hist[i+1]
        if centerCount > leftCount && centerCount > rightCount && centerCount > 100{
            
            localMaxes.append(-binLeftEdges[i])
        }
    }
    print(hist)
    return localMaxes
}

