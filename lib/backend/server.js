const express = require('express');
const http = require('http');
const mongoose = require('mongoose');
const socketIo = require('socket.io');
const cors = require('cors');
const crypto = require('crypto');
const { v4: uuidv4 } = require('uuid');

// 익스프레스 앱 설정
const app = express();
app.use(express.json());
app.use(cors());

// MongoDB 연결 모니터링 추가
mongoose.connect('mongodb://localhost:27017/anonymous-chat', {
  useNewUrlParser: true,
  useUnifiedTopology: true
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
  participants: [{ type: String }]
});

const messageSchema = new mongoose.Schema({
  messageId: { type: String, required: true, unique: true },
  roomId: { type: String, required: true },
  sender: { type: String, required: true },
  content: { type: String, required: true },
  senderAnonymousId: { type: Number },
  senderNickname: { type: String },
  senderUniqueId: { type: String },
  createdAt: { type: Date, default: Date.now }
});

// 모델 생성
const User = mongoose.model('User', userSchema);
const Room = mongoose.model('Room', roomSchema);
const Message = mongoose.model('Message', messageSchema);

// HTTP 서버 생성
const server = http.createServer(app);

// Socket.io 서버 설정
const io = socketIo(server, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST']
  }
});

// 라우트 설정
// 익명 사용자 생성
app.post('/api/users', async (req, res) => {
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
app.post('/api/rooms', async (req, res) => {
  try {
    console.log('채팅방 생성 요청:', req.body);
    const { name, creatorTempId } = req.body;

    const roomId = uuidv4();

    const newRoom = new Room({
      roomId,
      name,
      participants: [creatorTempId]
    });

    await newRoom.save();
    console.log(`채팅방 생성 성공: ${roomId}, 이름: ${name}`);

    res.status(201).json({
      success: true,
      data: {
        roomId: newRoom.roomId,
        name: newRoom.name
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
app.post('/api/rooms/:roomId/join', async (req, res) => {
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
      message: '채팅방 참가 성공'
    });
  } catch (error) {
    console.error('채팅방 참가 실패:', error);
    res.status(500).json({ success: false, message: '채팅방 참가 실패' });
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
  socket.on('join_room', (roomId) => {
    socket.join(roomId);
    console.log(`클라이언트 ${socket.id}가 채팅방 ${roomId}에 입장했습니다.`);
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

      // 채팅방 존재 여부 확인
      const room = await Room.findOne({ roomId });
      if (!room) {
        console.error(`메시지 전송 실패: 채팅방 ${roomId}를 찾을 수 없음`);
        socket.emit('message_error', {
          message: '채팅방을 찾을 수 없습니다.',
          messageData
        });
        return;
      }

      // 메시지 저장
      const newMessage = new Message({
        messageId,
        roomId,
        sender,
        content,
        senderAnonymousId,
        senderNickname,
        senderUniqueId
      });

      console.log('메시지 저장 시도:', {
        messageId,
        roomId,
        sender: sender.substring(0, 10) + '...',  // 개인정보 일부만 로그
        contentLength: content.length,
        senderAnonymousId,
        senderNickname,
        senderUniqueId
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
        createdAt: savedMessage.createdAt
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

  // 연결 해제
  socket.on('disconnect', (reason) => {
    console.log(`클라이언트 연결 해제: ${socket.id}, 이유: ${reason}`);
  });
});

// 서버 상태 체크 API 추가
app.get('/api/status', (req, res) => {
  res.status(200).json({
    success: true,
    message: '서버가 정상적으로 동작 중입니다.',
    time: new Date().toISOString(),
    socketConnections: io.engine.clientsCount
  });
});

// 서버 시작
const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`서버가 포트 ${PORT}에서 실행 중입니다.`);
  console.log(`소켓 서버가 포트 ${PORT}에서 실행 중입니다.`);
});