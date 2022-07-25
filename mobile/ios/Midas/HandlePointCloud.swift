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

func getTrueLidarPointCloud(logFrame: ARFrameDataLog) -> [simd_float3] {
    var depthData = logFrame.depthData
    let confidence = logFrame.confData
    depthData = depthData.filter{confidence[depthData.firstIndex(of: $0)!].rawValue == 2}
    return depthData.map({ point in point.w * simd_float3(point.x, point.y, point.z) })
}

func getGlobalPointCloud(logFrame: ARFrameDataLog, truePointCloud: [simd_float3]) -> [simd_float3] {
    let pose = logFrame.pose
    let globalPointCloud = truePointCloud.map({ point in pose * simd_float4(point, 1) })
    let theta = atan2(pose[0][2], pose[2][2])
    let yAxis = simd_float3(0, 1, 0)
    let rotationMatrix = float4x4(simd_quatf(angle: -theta, axis: yAxis))
    let yawAdjustedPointCloud = globalPointCloud.map({ point in rotationMatrix * point })
    return yawAdjustedPointCloud.map({point in simd_float3(point[0], point[1], point[2])})
}

func isolateObstacles(logFrame: ARFrameDataLog, yawAdjustedPointCloud: [simd_float3]) -> [simd_float3] {
    let depthOffset = yawAdjustedPointCloud.map({ point in point[2]}).max()
    var filteredPointCloud = yawAdjustedPointCloud.map({ point in simd_float3(point[0], point[1], point[2] - depthOffset!)})
    filteredPointCloud = filteredPointCloud.filter{$0[2] >= -4}
    let xValues = filteredPointCloud.map({ point in point[0]})
    let xOffset = (xValues.max()! + xValues.min()!) / 2
    let yOffset = filteredPointCloud.map({point in point[1]}).min()
    filteredPointCloud = filteredPointCloud.map({ point in simd_float3(point[0] - xOffset, point[1] - yOffset!, point[2])})
    filteredPointCloud = filteredPointCloud.filter{abs($0[0]) <= 0.5 && $0[1] > 0.25}
    return filteredPointCloud
}

func findObstacles(filteredPointCloud: [simd_float3]) -> [Float] {
    let zValues = filteredPointCloud.map({ point in point[2]})
    // TODO: convert binLeftEdges to meters (use Float)
    let minZValue = Float(0)
    let maxZValue = Float(-5)
    let stepSize = Float(-0.1)
    let binLeftEdges = Array(stride(from: minZValue, through: maxZValue, by: stepSize))
    var hist: [Int] = []
    for binEdge in binLeftEdges {
        let leftEdge = binEdge
        let rightEdge = binEdge + stepSize  // TODO: get rid of this magic number using a linspace approach
        let filteredZValues = zValues.filter({z in z >= leftEdge && z < rightEdge})
        let numberInBin = filteredZValues.count
        hist.append(numberInBin)
    }
    var localMaxes : [Float] = []
    for i in 1..<binLeftEdges.count-1 {
        let leftCount = hist[i-1]
        let centerCount = hist[i]
        let rightCount = hist[i+1]
        if centerCount > leftCount && centerCount > rightCount {
            localMaxes.append(binLeftEdges[i])
        }
    }
    return localMaxes
}

