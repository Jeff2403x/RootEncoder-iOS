//
//  H264FlvPacket.swift
//  app
//
//  Created by Pedro  on 19/9/23.
//  Copyright © 2023 pedroSG94. All rights reserved.
//

import Foundation

public class H264FlvPacket {
    
    private let TAG = "H264Packet"

    private var header = [UInt8](repeating: 0, count: 5)
    private let naluSize = 4
    private var configSend = false
    private var sps: Array<UInt8>? = nil
    private var pps: Array<UInt8>? = nil
    var profileIop = ProfileIop.BASELINE
    
    enum VideoType: UInt8 {
        case SEQUENCE = 0x00
        case NALU = 0x01
        case EO_SEQ = 0x02
    }
    
    func setVideoInfo(sps: Array<UInt8>, pps: Array<UInt8>) {
        self.sps = sps
        self.pps = pps
    }
    
    func createFlvVideoPacket(data: Frame, callback: (FlvPacket) -> Void) {
        let ts = data.timeStamp! / 1000
        let cts = 0
        header[2] = UInt8(cts >> 16)
        header[3] = UInt8(cts >> 8)
        header[4] = UInt8(cts)
        
        var buffer = [UInt8]()
        
        if !configSend {
            header[0] = UInt8((Int(VideoDataType.KEYFRAME.rawValue) << 4) | VideoFormat.AVC.rawValue)
            header[1] = VideoType.SEQUENCE.rawValue
            
            if let sps = self.sps, let pps = self.pps {
                let config = VideoSpecificConfigAVC(sps: sps, pps: pps, profileIop: profileIop)
                buffer = [UInt8](repeating: 0, count: config.size + header.count)
                config.write(buffer: &buffer, offset: header.count)
            } else {
                print("\(TAG): waiting for a valid sps and pps")
                return
            }
            
            buffer[0..<header.count] = header[0..<header.count]
            callback(FlvPacket(buffer: buffer, timeStamp: Int64(ts), length: buffer.count, type: .VIDEO))
            configSend = true
        }
        
        let headerSize = getHeaderSize(byteBuffer: data.buffer!)
        
        if headerSize == 0 {
            return
        }
        
        let validBuffer = removeHeader(byteBuffer: data.buffer!, size: headerSize)
        let size = validBuffer.count
        buffer = [UInt8](repeating: 0, count: header.count + size + naluSize)
        
        let type: Int = Int(validBuffer[0]) & 0x1F
        var nalType = VideoDataType.INTER_FRAME.rawValue
        
        if type == VideoNalType.IDR.rawValue {
            nalType = VideoDataType.KEYFRAME.rawValue
        } else if type == VideoNalType.SPS.rawValue || type == VideoNalType.PPS.rawValue {
            return
        }
        
        header[0] = UInt8((Int(nalType) << 4) | VideoFormat.AVC.rawValue)
        header[1] = VideoType.NALU.rawValue
        writeNaluSize(buffer: &buffer, offset: header.count, size: size)
        
        for i in 0..<size {
            buffer[header.count + naluSize + i] = validBuffer[i]
        }
        
        buffer[0..<header.count] = header[0..<header.count]
        callback(FlvPacket(buffer: buffer, timeStamp: Int64(ts), length: buffer.count, type: .VIDEO))
    }
    
    private func getHeaderSize(byteBuffer: [UInt8]) -> Int {
        guard let sps = self.sps, let pps = self.pps else {
            return 0
        }
        
        let startCodeSize = getStartCodeSize(byteBuffer: byteBuffer)
        return startCodeSize
    }
    
    private func getStartCodeSize(byteBuffer: [UInt8]) -> Int {
            if byteBuffer[0] == 0x00 && byteBuffer[1] == 0x00
                && byteBuffer[2] == 0x00 && byteBuffer[3] == 0x01 {
                return 4 // match 00 00 00 01
            } else if byteBuffer[0] == 0x00 && byteBuffer[1] == 0x00 && byteBuffer[2] == 0x01 {
                return 3 // match 00 00 01
            }
            return 0
        }
        
    private func writeNaluSize(buffer: inout [UInt8], offset: Int, size: Int) {
        buffer[offset] = UInt8(size >> 24)
        buffer[offset + 1] = UInt8(size >> 16)
        buffer[offset + 2] = UInt8(size >> 8)
        buffer[offset + 3] = UInt8(size & 0xFF)
    }
    
    private func removeHeader(byteBuffer: [UInt8], size: Int = -1) -> [UInt8] {
        let position = (size == -1) ? getStartCodeSize(byteBuffer: byteBuffer) : size
        return Array(byteBuffer[position..<byteBuffer.count])
    }
    
    func reset(resetInfo: Bool = true) {
        if resetInfo {
            sps = nil
            pps = nil
        }
        configSend = false
    }
}