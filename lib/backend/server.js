const express = require('express');
const http = require('http');
const mongoose = require('mongoose');
const socketIo = require('socket.io');
const cors = require('cors');
const crypto = require('crypto');
const axios = require('axios'); // PhishTank API 호출용
const { v4: uuidv4 } = require('uuid');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
require('dotenv').config();

// 익스프레스 앱 설정
const app = express();

// 보안 미들웨어 설정
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:"],
      connectSrc: ["'self'", "ws:", "wss:"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      mediaSrc: ["'self'"],
      frameSrc: ["'none'"],
    },
  },
  crossOriginEmbedderPolicy: false
}));

// Rate Limiting 설정
const generalLimiter = rateLimit({
  windowMs: parseInt(process.env.RATE_LIMIT_WINDOW_MS) || 15 * 60 * 1000, // 15분
  max: parseInt(process.env.RATE_LIMIT_MAX_REQUESTS) || 100, // 최대 100 요청
  message: {
    error: '너무 많은 요청이 감지되었습니다. 잠시 후 다시 시도해주세요.',
    retryAfter: '15분'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

const messageLimiter = rateLimit({
  windowMs: parseInt(process.env.MESSAGE_RATE_LIMIT_WINDOW_MS) || 60 * 1000, // 1분
  max: parseInt(process.env.MESSAGE_RATE_LIMIT_MAX_REQUESTS) || 20, // 최대 20 메시지
  message: {
    error: '메시지 전송 속도가 너무 빠릅니다. 잠시 후 다시 시도해주세요.',
    retryAfter: '1분'
  },
  standardHeaders: true,
  legacyHeaders: false,
});

// 미들웨어 적용
app.use(generalLimiter);
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// CORS 설정
const corsOptions = {
  origin: process.env.CORS_ORIGIN || '*',
  methods: process.env.CORS_METHODS ? process.env.CORS_METHODS.split(',') : ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  credentials: true
};
app.use(cors(corsOptions));

// MongoDB 연결 모니터링 추가
const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/anonymous-chat';
mongoose.connect(mongoUri, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  maxPoolSize: 10,
  serverSelectionTimeoutMS: 5000,
  socketTimeoutMS: 45000,
}).then(() => console.log('MongoDB 연결 성공'))
  .catch(err => console.error('MongoDB 연결 실패:', err));

// MongoDB 연결 상태 모니터링
mongoose.connection.on('connected', () => {
  console.log('MongoDB에 연결되었습니다.');
});

mongoose.connection.on('error', (err) => {
  console.error('MongoDB 연결 오류:', err);
});

mongoose.connection.on('disconnected', () => {
  console.log('MongoDB 연결이 끊어졌습니다.');
});

// 스키마 정의
const userSchema = new mongoose.Schema({
  userId: { type: String, required: true, unique: true },
  nickname: { type: String, default: '' },
  tempId: { type: String, required: true, unique: true },
  anonymousId: { type: Number },
  uniqueIdentifier: { type: String, required: true },
  publicKey: { type: String },
  createdAt: { type: Date, default: Date.now }
});

const roomSchema = new mongoose.Schema({
  roomId: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  createdAt: { type: Date, default: Date.now },
  participants: [{ type: String }],
  securityEnabled: { type: Boolean, default: true },
  securityLevel: { type: String, default: 'basic' } // basic, strict, custom
});

const messageSchema = new mongoose.Schema({
  messageId: { type: String, required: true, unique: true },
  roomId: { type: String, required: true },
  sender: { type: String, required: true },
  content: { type: String, required: true },
  senderAnonymousId: { type: Number },
  senderNickname: { type: String },
  senderUniqueId: { type: String },
  securityChecked: { type: Boolean, default: false },
  securityResult: {
    isThreat: { type: Boolean, default: false },
    threatLevel: { type: String, default: 'safe' },
    threatType: { type: String, default: 'none' },
    confidenceScore: { type: Number, default: 0 },
    detectedKeywords: [{ type: String }],
    reason: { type: String, default: '' }
  },
  createdAt: { type: Date, default: Date.now }
});

// 보안 로그 스키마
const securityLogSchema = new mongoose.Schema({
  logId: { type: String, required: true, unique: true },
  messageId: { type: String, required: true },
  roomId: { type: String, required: true },
  userId: { type: String, required: true },
  threatDetected: { type: Boolean, default: false },
  threatLevel: { type: String, default: 'safe' },
  threatType: { type: String, default: 'none' },
  detectedKeywords: [{ type: String }],
  action: { type: String, default: 'allow' }, // allow, warn, block
  timestamp: { type: Date, default: Date.now }
});

// PhishTank 캐시 스키마
const phishTankCacheSchema = new mongoose.Schema({
  url: { type: String, required: true, unique: true },
  isPhishing: { type: Boolean, required: true },
  checkedAt: { type: Date, default: Date.now },
  expiresAt: { type: Date, required: true }
});

// 모델 생성
const User = mongoose.model('User', userSchema);
const Room = mongoose.model('Room', roomSchema);
const Message = mongoose.model('Message', messageSchema);
const SecurityLog = mongoose.model('SecurityLog', securityLogSchema);
const PhishTankCache = mongoose.model('PhishTankCache', phishTankCacheSchema);

// HTTP 서버 생성
const server = http.createServer(app);

// Socket.io 서버 설정
const io = socketIo(server, {
  cors: corsOptions,
  pingTimeout: parseInt(process.env.SOCKET_PING_TIMEOUT) || 60000,
  pingInterval: parseInt(process.env.SOCKET_PING_INTERVAL) || 25000,
  maxHttpBufferSize: 1e6, // 1MB
  allowEIO3: true
});

// PhishTank API 설정
const PHISHTANK_BASE_URL = 'https://checkurl.phishtank.com/checkurl/';
const PHISHTANK_CACHE_DURATION = (parseInt(process.env.PHISHTANK_CACHE_DURATION_HOURS) || 24) * 60 * 60 * 1000; // 기본 24시간
const PHISHTANK_API_KEY = process.env.PHISHTANK_API_KEY;

// PhishTank URL 검사 함수
async function checkPhishTankUrl(url, apiKey = PHISHTANK_API_KEY) {
  try {
    // 캐시 확인
    const cached = await PhishTankCache.findOne({
      url: url,
      expiresAt: { $gt: new Date() }
    });

    if (cached) {
      console.log(`PhishTank 캐시 히트: ${url}`);
      return cached.isPhishing;
    }

    // API 호출
    const requestData = {
      url: url,
      format: 'json'
    };

    if (apiKey) {
      requestData.app_key = apiKey;
    }

    const response = await axios.post(PHISHTANK_BASE_URL, requestData, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'TreeHideout-AnonymousChat/1.0'
      },
      timeout: 10000
    });

    let isPhishing = false;
    if (response.data && response.data.results && response.data.results.length > 0) {
      isPhishing = response.data.results[0].in_database === true;
    }

    // 캐시에 저장
    const expiresAt = new Date(Date.now() + PHISHTANK_CACHE_DURATION);
    await PhishTankCache.findOneAndUpdate(
      { url: url },
      {
        url: url,
        isPhishing: isPhishing,
        checkedAt: new Date(),
        expiresAt: expiresAt
      },
      { upsert: true }
    );

    console.log(`PhishTank API 결과: ${url} -> ${isPhishing ? '피싱' : '안전'}`);
    return isPhishing;

  } catch (error) {
    console.error('PhishTank API 오류:', error.message);
    return false; // 오류 시 안전하다고 가정
  }
}

// URL 추출 함수
function extractUrls(text) {
  const urlRegex = /https?:\/\/[^\s]+|www\.[^\s]+|[a-zA-Z0-9-]+\.[a-zA-Z]{2,}[^\s]*/gi;
  return text.match(urlRegex) || [];
}

// 기본 보안 키워드 검사 함수
function checkBasicSecurity(content) {
  const highRiskKeywords = [
    '계정이 해킹되었습니다', '즉시 확인이 필요합니다', '계정이 정지됩니다',
    '무료 비트코인', '투자 수익률 보장', '피싱 사이트', '가짜 웹사이트',
    'account suspended', 'verify account', 'click here now', 'urgent action required',
    'phishing attempt', 'malware detected', 'suspicious activity'
  ];

  const mediumRiskKeywords = [
    '계정 확인', '비밀번호 변경', '로그인 확인', '카드 번호', '계좌 번호',
    'verify identity', 'update password', 'confirm account', 'credit card number'
  ];

  const detectedKeywords = [];
  let riskScore = 0;

  // 고위험 키워드 검사
  for (const keyword of highRiskKeywords) {
    if (content.toLowerCase().includes(keyword.toLowerCase())) {
      detectedKeywords.push(keyword);
      riskScore += 3;
    }
  }

  // 중위험 키워드 검사
  for (const keyword of mediumRiskKeywords) {
    if (content.toLowerCase().includes(keyword.toLowerCase())) {
      detectedKeywords.push(keyword);
      riskScore += 1.5;
    }
  }

  // URL 단축 서비스 검사
  const shortUrlPatterns = ['bit.ly', 'tinyurl.com', 't.co', 'goo.gl'];
  for (const pattern of shortUrlPatterns) {
    if (content.includes(pattern)) {
      detectedKeywords.push(pattern);
      riskScore += 1;
    }
  }

  const confidenceScore = Math.min(riskScore / 10, 1); // 0-1 사이로 정규화
  const isThreat = confidenceScore >= 0.3;

  let threatLevel = 'safe';
  if (confidenceScore >= 0.8) threatLevel = 'critical';
  else if (confidenceScore >= 0.6) threatLevel = 'high';
  else if (confidenceScore >= 0.4) threatLevel = 'medium';
  else if (confidenceScore >= 0.2) threatLevel = 'low';

  return {
    isThreat,
    threatLevel,
    threatType: isThreat ? 'suspicious_content' : 'safe',
    confidenceScore,
    detectedKeywords,
    reason: isThreat ? '의심스러운 키워드가 탐지되었습니다.' : '안전한 메시지입니다.'
  };
}

// 통합 보안 검사 함수
async function performSecurityCheck(content, securityMode = 'basic', apiKey = null) {
  const securityResult = {
    isThreat: false,
    threatLevel: 'safe',
    threatType: 'safe',
    confidenceScore: 0,
    detectedKeywords: [],
    reason: '안전한 메시지입니다.'
  };

  try {
    // 기본 키워드 검사
    const basicResult = checkBasicSecurity(content);
    Object.assign(securityResult, basicResult);

    // PhishTank 검사 (URL이 있는 경우)
    if (securityMode === 'phishtank' || securityMode === 'hybrid') {
      const urls = extractUrls(content);
      for (const url of urls) {
        const isPhishing = await checkPhishTankUrl(url, apiKey);
        if (isPhishing) {
          securityResult.isThreat = true;
          securityResult.threatLevel = 'critical';
          securityResult.threatType = 'phishing_url';
          securityResult.confidenceScore = 1.0;
          securityResult.detectedKeywords.push(url);
          securityResult.reason = 'PhishTank에서 확인된 피싱 URL이 탐지되었습니다.';
          break;
        }
      }
    }

    return securityResult;

  } catch (error) {
    console.error('보안 검사 오류:', error);
    return securityResult; // 오류 시 기본값 반환
  }
}

// 보안 로그 저장 함수
async function saveSecurityLog(messageId, roomId, userId, securityResult, action = 'allow') {
  try {
    const securityLog = new SecurityLog({
      logId: uuidv4(),
      messageId,
      roomId,
      userId,
      threatDetected: securityResult.isThreat,
      threatLevel: securityResult.threatLevel,
      threatType: securityResult.threatType,
      detectedKeywords: securityResult.detectedKeywords,
      action
    });

    await securityLog.save();
    console.log(`보안 로그 저장됨: ${messageId}`);
  } catch (error) {
    console.error('보안 로그 저장 실패:', error);
  }
}

// 라우트 설정
// 익명 사용자 생성
app.post('/api/users', messageLimiter, async (req, res) => {
  try {
    console.log('사용자 생성 요청:', req.body);
    const nickname = req.body.nickname || '';
    let uniqueIdentifier = req.body.uniqueIdentifier;

    if (!uniqueIdentifier) {
      const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
      uniqueIdentifier = '';

      for (let i = 0; i < 4; i++) {
        uniqueIdentifier += alphabet.charAt(Math.floor(Math.random() * alphabet.length));
      }

      uniqueIdentifier += (100 + Math.floor(Math.random() * 900)).toString();
    }

    const tempId = crypto.randomBytes(16).toString('hex');
    const userId = uuidv4();
    const anonymousId = 1000 + Math.floor(Math.random() * 9000);

    const newUser = new User({
      userId,
      nickname,
      tempId,
      anonymousId,
      uniqueIdentifier
    });

    await newUser.save();

    console.log(`사용자 생성 성공: ${userId}, 닉네임: ${nickname || '(익명)'}, 식별번호: ${uniqueIdentifier}`);

    res.status(201).json({
      success: true,
      data: {
        userId: newUser.userId,
        nickname: newUser.nickname,
        tempId: newUser.tempId,
        anonymousId,
        uniqueIdentifier
      }
    });
  } catch (error) {
    console.error('사용자 생성 실패:', error);
    res.status(500).json({ success: false, message: '사용자 생성 실패' });
  }
});

// 채팅방 생성
app.post('/api/rooms', messageLimiter, async (req, res) => {
  try {
    console.log('채팅방 생성 요청:', req.body);
    const { name, creatorTempId, securityEnabled = true, securityLevel = 'basic' } = req.body;

    const roomId = uuidv4();

    const newRoom = new Room({
      roomId,
      name,
      participants: [creatorTempId],
      securityEnabled,
      securityLevel
    });

    await newRoom.save();
    console.log(`채팅방 생성 성공: ${roomId}, 이름: ${name}, 보안: ${securityEnabled}`);

    res.status(201).json({
      success: true,
      data: {
        roomId: newRoom.roomId,
        name: newRoom.name,
        securityEnabled: newRoom.securityEnabled,
        securityLevel: newRoom.securityLevel
      }
    });
  } catch (error) {
    console.error('채팅방 생성 실패:', error);
    res.status(500).json({ success: false, message: '채팅방 생성 실패' });
  }
});

// 채팅방 목록 조회
app.get('/api/rooms', async (req, res) => {
  try {
    console.log('채팅방 목록 조회 요청');
    const rooms = await Room.find().sort({ createdAt: -1 });
    console.log(`채팅방 목록 조회 성공: ${rooms.length}개의 방을 찾음`);

    res.status(200).json({
      success: true,
      data: rooms
    });
  } catch (error) {
    console.error('채팅방 목록 조회 실패:', error);
    res.status(500).json({ success: false, message: '채팅방 목록 조회 실패' });
  }
});

// 채팅방의 이전 메시지 목록 조회 API
app.get('/api/rooms/:roomId/messages', async (req, res) => {
  try {
    const { roomId } = req.params;
    console.log(`메시지 목록 조회 요청: 방 ID ${roomId}`);

    // 채팅방 존재 여부 확인
    const room = await Room.findOne({ roomId });
    if (!room) {
      console.log(`해당 채팅방을 찾을 수 없음: ${roomId}`);
      return res.status(404).json({ success: false, message: '채팅방을 찾을 수 없습니다.' });
    }

    // 해당 채팅방의 메시지 목록 조회
    const messages = await Message.find({ roomId }).sort({ createdAt: 1 });
    console.log(`메시지 목록 조회 성공: 방 ID ${roomId}, ${messages.length}개의 메시지 찾음`);

    res.status(200).json({
      success: true,
      data: messages
    });
  } catch (error) {
    console.error('메시지 목록 조회 실패:', error);
    res.status(500).json({ success: false, message: '메시지 목록 조회 실패' });
  }
});

// 채팅방 참가
app.post('/api/rooms/:roomId/join', messageLimiter, async (req, res) => {
  try {
    const { roomId } = req.params;
    const { tempId } = req.body;
    console.log(`채팅방 참가 요청: 방 ID ${roomId}, 사용자 tempId ${tempId}`);

    const room = await Room.findOne({ roomId });

    if (!room) {
      console.log(`해당 채팅방을 찾을 수 없음: ${roomId}`);
      return res.status(404).json({ success: false, message: '채팅방을 찾을 수 없습니다.' });
    }

    // 이미 참가한 사용자인지 확인
    if (!room.participants.includes(tempId)) {
      room.participants.push(tempId);
      await room.save();
      console.log(`채팅방 참가 성공: 방 ID ${roomId}, 사용자 tempId ${tempId}`);
    } else {
      console.log(`채팅방에 이미 참가한 사용자: 방 ID ${roomId}, 사용자 tempId ${tempId}`);
    }

    res.status(200).json({
      success: true,
      message: '채팅방 참가 성공',
      roomInfo: {
        securityEnabled: room.securityEnabled,
        securityLevel: room.securityLevel
      }
    });
  } catch (error) {
    console.error('채팅방 참가 실패:', error);
    res.status(500).json({ success: false, message: '채팅방 참가 실패' });
  }
});

// 보안 통계 조회 API
app.get('/api/security/stats', async (req, res) => {
  try {
    const { roomId, userId, startDate, endDate } = req.query;

    let query = {};
    if (roomId) query.roomId = roomId;
    if (userId) query.userId = userId;
    if (startDate || endDate) {
      query.timestamp = {};
      if (startDate) query.timestamp.$gte = new Date(startDate);
      if (endDate) query.timestamp.$lte = new Date(endDate);
    }

    const logs = await SecurityLog.find(query);

    const stats = {
      totalChecks: logs.length,
      threatsDetected: logs.filter(log => log.threatDetected).length,
      threatsByLevel: {
        safe: logs.filter(log => log.threatLevel === 'safe').length,
        low: logs.filter(log => log.threatLevel === 'low').length,
        medium: logs.filter(log => log.threatLevel === 'medium').length,
        high: logs.filter(log => log.threatLevel === 'high').length,
        critical: logs.filter(log => log.threatLevel === 'critical').length
      },
      actionsTaken: {
        allow: logs.filter(log => log.action === 'allow').length,
        warn: logs.filter(log => log.action === 'warn').length,
        block: logs.filter(log => log.action === 'block').length
      }
    };

    res.status(200).json({
      success: true,
      data: stats
    });
  } catch (error) {
    console.error('보안 통계 조회 실패:', error);
    res.status(500).json({ success: false, message: '보안 통계 조회 실패' });
  }
});

// PhishTank 상태 확인 API
app.get('/api/security/phishtank/status', async (req, res) => {
  try {
    // 캐시 통계
    const cacheCount = await PhishTankCache.countDocuments();
    const expiredCount = await PhishTankCache.countDocuments({
      expiresAt: { $lt: new Date() }
    });

    res.status(200).json({
      success: true,
      data: {
        cacheSize: cacheCount,
        expiredEntries: expiredCount,
        activeEntries: cacheCount - expiredCount
      }
    });
  } catch (error) {
    console.error('PhishTank 상태 확인 실패:', error);
    res.status(500).json({ success: false, message: 'PhishTank 상태 확인 실패' });
  }
});

// PhishTank 캐시 초기화 API
app.delete('/api/security/phishtank/cache', async (req, res) => {
  try {
    await PhishTankCache.deleteMany({});
    console.log('PhishTank 캐시 초기화 완료');

    res.status(200).json({
      success: true,
      message: 'PhishTank 캐시가 초기화되었습니다'
    });
  } catch (error) {
    console.error('PhishTank 캐시 초기화 실패:', error);
    res.status(500).json({ success: false, message: 'PhishTank 캐시 초기화 실패' });
  }
});

// Socket.io 연결 처리
io.on('connection', (socket) => {
  console.log('새로운 클라이언트 연결:', socket.id);

  // 소켓 연결 오류 처리
  socket.on('error', (error) => {
    console.error('소켓 오류:', error);
  });

  // 채팅방 입장
  socket.on('join_room', async (roomId) => {
    socket.join(roomId);
    console.log(`클라이언트 ${socket.id}가 채팅방 ${roomId}에 입장했습니다.`);

    // 방 정보 전송 (보안 설정 포함)
    try {
      const room = await Room.findOne({ roomId });
      if (room) {
        socket.emit('room_info', {
          securityEnabled: room.securityEnabled,
          securityLevel: room.securityLevel
        });
      }
    } catch (error) {
      console.error('방 정보 조회 실패:', error);
    }
  });

  // 채팅방 퇴장
  socket.on('leave_room', (roomId) => {
    socket.leave(roomId);
    console.log(`클라이언트 ${socket.id}가 채팅방 ${roomId}에서 퇴장했습니다.`);
  });

  // 메시지 수신 및 브로드캐스팅
  socket.on('send_message', async (messageData) => {
    try {
      console.log('메시지 수신:', messageData);
      const { messageId: clientMessageId, roomId, sender, content, senderAnonymousId, senderNickname, senderUniqueId } = messageData;

      // 메시지 ID 사용 또는 생성
      const messageId = clientMessageId || uuidv4();

      // 채팅방 존재 여부 및 보안 설정 확인
      const room = await Room.findOne({ roomId });
      if (!room) {
        console.error(`메시지 전송 실패: 채팅방 ${roomId}를 찾을 수 없음`);
        socket.emit('message_error', {
          message: '채팅방을 찾을 수 없습니다.',
          messageData
        });
        return;
      }

      // 보안 검사 수행
      let securityResult = {
        isThreat: false,
        threatLevel: 'safe',
        threatType: 'safe',
        confidenceScore: 0,
        detectedKeywords: [],
        reason: '안전한 메시지입니다.'
      };

      if (room.securityEnabled) {
        console.log(`보안 검사 수행: 모드=${room.securityLevel}, 내용=${content.substring(0, 50)}...`);
        securityResult = await performSecurityCheck(content, room.securityLevel);

        // 보안 로그 저장
        const action = securityResult.isThreat ?
          (securityResult.threatLevel === 'critical' || securityResult.threatLevel === 'high' ? 'block' : 'warn') :
          'allow';

        await saveSecurityLog(messageId, roomId, sender, securityResult, action);

        // 위험한 메시지 차단 (설정에 따라)
        if (securityResult.isThreat && securityResult.confidenceScore >= 0.7) {
          console.log(`메시지 차단됨: ${messageId}, 위험도: ${securityResult.confidenceScore}`);
          socket.emit('message_blocked', {
            messageId,
            reason: securityResult.reason,
            threatLevel: securityResult.threatLevel,
            detectedKeywords: securityResult.detectedKeywords
          });
          return; // 메시지 전송 중단
        }
      }

      // 메시지 저장
      const newMessage = new Message({
        messageId,
        roomId,
        sender,
        content,
        senderAnonymousId,
        senderNickname,
        senderUniqueId,
        securityChecked: room.securityEnabled,
        securityResult: room.securityEnabled ? securityResult : undefined
      });

      console.log('메시지 저장 시도:', {
        messageId,
        roomId,
        sender: sender.substring(0, 10) + '...',  // 개인정보 일부만 로그
        contentLength: content.length,
        securityChecked: room.securityEnabled,
        threatDetected: securityResult.isThreat
      });

      const savedMessage = await newMessage.save();
      console.log(`메시지 저장 성공: ID ${messageId}, 방 ID ${roomId}`);

      // 같은 방에 있는 모든 클라이언트에게 메시지 전송
      const messageToSend = {
        messageId,
        roomId,
        sender,
        content,
        senderAnonymousId,
        senderNickname,
        senderUniqueId,
        createdAt: savedMessage.createdAt,
        securityInfo: room.securityEnabled ? {
          checked: true,
          isThreat: securityResult.isThreat,
          threatLevel: securityResult.threatLevel,
          hasWarning: securityResult.isThreat && securityResult.confidenceScore < 0.7
        } : { checked: false }
      };

      console.log(`메시지 브로드캐스팅: 방 ID ${roomId}, 메시지 ID ${messageId}`);
      io.to(roomId).emit('receive_message', messageToSend);

      console.log(`메시지가 채팅방 ${roomId}에 전송됨`);
    } catch (error) {
      console.error('메시지 전송 실패:', error);
      socket.emit('message_error', {
        message: '메시지 전송 실패',
        error: error.toString(),
        messageData
      });
    }
  });

  // 보안 검사 요청 (실시간)
  socket.on('security_check', async (data) => {
    try {
      const { content, securityMode = 'basic' } = data;
      console.log(`실시간 보안 검사 요청: ${content.substring(0, 50)}...`);

      const result = await performSecurityCheck(content, securityMode);

      socket.emit('security_result', {
        content,
        result,
        timestamp: new Date()
      });
    } catch (error) {
      console.error('실시간 보안 검사 실패:', error);
      socket.emit('security_error', {
        message: '보안 검사 실패',
        error: error.toString()
      });
    }
  });

  // 연결 해제
  socket.on('disconnect', (reason) => {
    console.log(`클라이언트 연결 해제: ${socket.id}, 이유: ${reason}`);
  });
});

// 서버 상태 체크 API 추가
app.get('/api/status', async (req, res) => {
  try {
    // 데이터베이스 연결 상태 확인
    const dbStatus = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected';

    // 기본 통계
    const userCount = await User.countDocuments();
    const roomCount = await Room.countDocuments();
    const messageCount = await Message.countDocuments();
    const securityLogCount = await SecurityLog.countDocuments();

    res.status(200).json({
      success: true,
      message: '서버가 정상적으로 동작 중입니다.',
      time: new Date().toISOString(),
      database: dbStatus,
      socketConnections: io.engine.clientsCount,
      statistics: {
        users: userCount,
        rooms: roomCount,
        messages: messageCount,
        securityLogs: securityLogCount
      }
    });
  } catch (error) {
    console.error('서버 상태 확인 실패:', error);
    res.status(500).json({
      success: false,
      message: '서버 상태 확인 실패',
      error: error.message
    });
  }
});

// 정기적으로 만료된 PhishTank 캐시 정리
setInterval(async () => {
  try {
    const result = await PhishTankCache.deleteMany({
      expiresAt: { $lt: new Date() }
    });
    if (result.deletedCount > 0) {
      console.log(`만료된 PhishTank 캐시 ${result.deletedCount}개 삭제됨`);
    }
  } catch (error) {
    console.error('PhishTank 캐시 정리 실패:', error);
  }
}, 60 * 60 * 1000); // 1시간마다 실행

// 서버 시작
const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`서버가 포트 ${PORT}에서 실행 중입니다.`);
  console.log(`소켓 서버가 포트 ${PORT}에서 실행 중입니다.`);
  console.log('AI 보안 검열 시스템이 활성화되었습니다.');
  console.log('PhishTank 통합 지원이 활성화되었습니다.');
});