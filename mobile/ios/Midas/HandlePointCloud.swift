//
//  HandlePointCloud.swift
//  Midas
//
//  Created by occamlab on 7/20/22.
//

import AVFoundation
import ARKit
import ARDataLogger

func getTrueLidarPointCloud(logFrame: ARFrameDataLog) -> [simd_float3] {
    let depthData = logFrame.depthData
    return depthData.map({ point in point.w * simd_float3(point.x, point.y, point.z) })
}

func getGlobalPointCloud(logFrame: ARFrameDataLog, truePointCloud: [simd_float3]) -> [simd_float3] {
    let pose = logFrame.pose
    var globalPointCloud = truePointCloud.map({ point in pose * simd_float4(point, 1) })
    let theta = atan2(pose[0][2], pose[2][2])
    let yAxis = simd_float3(0, 1, 0)
    let rotationMatrix = float4x4(simd_quatf(angle: -theta, axis: yAxis))
    // Multiply rotationMatrix and globalPointCloud
}
