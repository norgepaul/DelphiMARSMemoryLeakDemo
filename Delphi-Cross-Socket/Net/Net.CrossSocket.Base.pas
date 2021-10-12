﻿{******************************************************************************}
{                                                                              }
{       Delphi cross platform socket library                                   }
{                                                                              }
{       Copyright (c) 2017 WiNDDRiVER(soulawing@gmail.com)                     }
{                                                                              }
{       Homepage: https://github.com/winddriver/Delphi-Cross-Socket            }
{                                                                              }
{******************************************************************************}
unit Net.CrossSocket.Base;

// 是否将大块数据分成小块发送(仅IOCP下有效)
// 注意: 开启该开关的情况下, 同一个连接不要在一次发送尚未结束时开始另一次发送
//       否则会导致两块数据被分成小块后出现交错
{.$DEFINE __LITTLE_PIECE__}

{$IF defined(DEBUG) or defined(madExcept)}
  {$DEFINE __DEBUG__}
{$ENDIF}

interface

uses
  System.SysUtils,
  System.Classes,
  System.Math,
  System.Generics.Collections,
  Net.SocketAPI;

const
  // 唯一编号类别
  // 唯一编号共64位, 高2位用于表示类别
  UID_RAW        = $0;
  UID_LISTEN     = $1;
  UID_CONNECTION = $2;

  // 最大唯一编号(62个1)
  UID_MASK       = UInt64($3FFFFFFFFFFFFFFF);

  IPv4_ALL   = '0.0.0.0';
  IPv6_ALL   = '::';
  IPv4v6_ALL = '';
  IPv4_LOCAL = '127.0.0.1';
  IPv6_LOCAL = '::1';

type
  ECrossSocket = class(Exception);

  ICrossSocket = interface;
  ICrossListen = interface;
  ICrossConnection = interface;
  TAbstractCrossSocket = class;
  TIoEventThread = class;

  /// <summary>
  ///   连接类型
  /// </summary>
  TConnectType = (
    /// <summary>
    ///   未知
    /// </summary>
    ctUnknown,
    /// <summary>
    ///   由监听Accept生成的连接
    /// </summary>
    ctAccept,
    /// <summary>
    ///   由Connect调用生成的连接
    /// </summary>
    ctConnect);

  /// <summary>
  ///   连接状态
  /// </summary>
  TConnectStatus = (
    /// <summary>
    ///   未知
    /// </summary>
    csUnknown,
    /// <summary>
    ///   正在连接
    /// </summary>
    csConnecting,
    /// <summary>
    ///   正在握手(SSL)
    /// </summary>
    csHandshaking,
    /// <summary>
    ///   已连接
    /// </summary>
    csConnected,
    /// <summary>
    ///   已断开
    /// </summary>
    csDisconnected,
    /// <summary>
    ///   已关闭
    /// </summary>
    csClosed);

  TCrossListenCallback = reference to procedure(const AListen: ICrossListen; const AResult: Boolean);
  TCrossConnectionCallback = reference to procedure(const AConnection: ICrossConnection; const AResult: Boolean);

  /// <summary>
  ///   基础数据接口
  /// </summary>
  ICrossData = interface
  ['{988404A3-D297-4C6D-9A76-16E50553596E}']
    function GetOwner: ICrossSocket;
    function GetUID: UInt64;
    function GetSocket: THandle;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean;
    function GetUserData: Pointer;
    function GetUserObject: TObject;
    function GetUserInterface: IInterface;

    procedure SetUserData(const AValue: Pointer);
    procedure SetUserObject(const AValue: TObject);
    procedure SetUserInterface(const AValue: IInterface);

    /// <summary>
    ///   更新套接字地址信息
    /// </summary>
    /// <remarks>
    ///   LocalAddr, LocalPort, PeerAddr, PeerPort 都依赖于该方法
    /// </remarks>
    procedure UpdateAddr;

    /// <summary>
    ///   关闭套接字
    /// </summary>
    procedure Close;

    /// <summary>
    ///   宿主对象
    /// </summary>
    property Owner: ICrossSocket read GetOwner;

    /// <summary>
    ///   唯一编号
    /// </summary>
    property UID: UInt64 read GetUID;

    /// <summary>
    ///   套接字句柄
    /// </summary>
    property Socket: THandle read GetSocket;

    /// <summary>
    ///   本地IP地址
    /// </summary>
    property LocalAddr: string read GetLocalAddr;

    /// <summary>
    ///   本地端口
    /// </summary>
    property LocalPort: Word read GetLocalPort;

    /// <summary>
    ///   是否已关闭
    /// </summary>
    property IsClosed: Boolean read GetIsClosed;

    /// <summary>
    ///   用户数据(可以用于存储用户自定义的数据结构)
    /// </summary>
    property UserData: Pointer read GetUserData write SetUserData;

    /// <summary>
    ///   用户数据(可以用于存储用户自定义的数据结构)
    /// </summary>
    property UserObject: TObject read GetUserObject write SetUserObject;

    /// <summary>
    ///   用户数据(可以用于存储用户自定义的数据结构)
    /// </summary>
    property UserInterface: IInterface read GetUserInterface write SetUserInterface;
  end;
  TCrossDatas = TDictionary<UInt64, ICrossData>;

  /// <summary>
  ///   监听接口
  /// </summary>
  ICrossListen = interface(ICrossData)
  ['{4008919E-8F16-4BBD-A68D-2FD1DE630702}']
    function GetFamily: Integer;
    function GetSockType: Integer;
    function GetProtocol: Integer;

    /// <summary>
    ///   PF_xxx
    /// </summary>
    property Family: Integer read GetFamily;

    /// <summary>
    ///   SOCK_xxx
    /// </summary>
    property SockType: Integer read GetSockType;

    /// <summary>
    ///   IPPROTO_xxx
    /// </summary>
    property Protocol: Integer read GetProtocol;
  end;
  TCrossListens = TDictionary<UInt64, ICrossListen>;

  /// <summary>
  ///   连接接口
  /// </summary>
  ICrossConnection = interface(ICrossData)
  ['{13C2A39E-C918-49B9-BBD3-A99110F94D1B}']
    function GetPeerAddr: string;
    function GetPeerPort: Word;
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;

    procedure SetConnectStatus(const AValue: TConnectStatus);

    /// <summary>
    ///   优雅关闭
    /// </summary>
    procedure Disconnect;

    /// <summary>
    ///   发送内存块数据
    /// </summary>
    /// <param name="ABuffer">
    ///   内存块指针
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBuf(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送无类型数据
    /// </summary>
    /// <param name="ABuffer">
    ///   无类型数据
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBuf(const ABuffer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="ABytes">
    ///   字节数据
    /// </param>
    /// <param name="AOffset">
    ///   偏移量
    /// </param>
    /// <param name="ACount">
    ///   数据大小
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBytes(const ABytes: TBytes; const AOffset, ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送字节数据
    /// </summary>
    /// <param name="ABytes">
    ///   字节数据
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    procedure SendBytes(const ABytes: TBytes;
      const ACallback: TCrossConnectionCallback = nil); overload;

    /// <summary>
    ///   发送数据流(用于发送较大的数据)
    /// </summary>
    /// <param name="AStream">
    ///   流数据
    /// </param>
    /// <param name="ACallback">
    ///   全部数据发送完成或者出错时调用的回调函数
    /// </param>
    /// <remarks>
    ///   由于是纯异步发送, 所以务必保证发送过程中 AStream 的有效性, 将 AStream 的释放放到回调函数中去 <br />
    /// </remarks>
    procedure SendStream(const AStream: TStream;
      const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   连接IP地址
    /// </summary>
    property PeerAddr: string read GetPeerAddr;

    /// <summary>
    ///   连接端口
    /// </summary>
    property PeerPort: Word read GetPeerPort;

    /// <summary>
    ///   连接类型
    /// </summary>
    /// <remarks>
    ///   <list type="bullet">
    ///     <item>
    ///       ctAccept, 由监听Accept生成的连接;
    ///     </item>
    ///     <item>
    ///       ctConnect, 由Connect调用生成的连接
    ///     </item>
    ///   </list>
    /// </remarks>
    property ConnectType: TConnectType read GetConnectType;

    /// <summary>
    ///   连接状态
    /// </summary>
    property ConnectStatus: TConnectStatus read GetConnectStatus write SetConnectStatus;
  end;
  TCrossConnections = TDictionary<UInt64, ICrossConnection>;

  TCrossIoThreadEvent = procedure(const Sender: TObject; const AIoThread: TIoEventThread) of object;
  TCrossListenEvent = procedure(const Sender: TObject; const AListen: ICrossListen) of object;
  TCrossConnectEvent = procedure(const Sender: TObject; const AConnection: ICrossConnection) of object;
  TCrossDataEvent = procedure(const Sender: TObject; const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer) of object;

  /// <summary>
  ///   跨平台Socket接口
  /// </summary>
  ICrossSocket = interface
  ['{2371CC3F-EB38-4C5D-8FA9-C913B9CD37A0}']
    function GetIoThreads: Integer;
    function GetConnectionsCount: Integer;
    function GetListensCount: Integer;

    function GetOnIoThreadBegin: TCrossIoThreadEvent;
    function GetOnIoThreadEnd: TCrossIoThreadEvent;
    function GetOnConnected: TCrossConnectEvent;
    function GetOnDisconnected: TCrossConnectEvent;
    function GetOnListened: TCrossListenEvent;
    function GetOnListenEnd: TCrossListenEvent;
    function GetOnReceived: TCrossDataEvent;
    function GetOnSent: TCrossDataEvent;

    procedure SetOnIoThreadBegin(const AValue: TCrossIoThreadEvent);
    procedure SetOnIoThreadEnd(const AValue: TCrossIoThreadEvent);
    procedure SetOnConnected(const AValue: TCrossConnectEvent);
    procedure SetOnDisconnected(const AValue: TCrossConnectEvent);
    procedure SetOnListened(const AValue: TCrossListenEvent);
    procedure SetOnListenEnd(const AValue: TCrossListenEvent);
    procedure SetOnReceived(const AValue: TCrossDataEvent);
    procedure SetOnSent(const AValue: TCrossDataEvent);

    /// <summary>
    ///   启动IO循环
    /// </summary>
    procedure StartLoop;

    /// <summary>
    ///   停止IO循环
    /// </summary>
    procedure StopLoop;

    /// <summary>
    ///   处理IO事件(内部使用)
    /// </summary>
    function ProcessIoEvent: Boolean;

    /// <summary>
    ///   监听端口
    /// </summary>
    /// <param name="AHost">
    ///   监听地址:
    ///   <list type="bullet">
    ///     <item>
    ///       要监听IPv4和IPv6所有地址, 请设置为空
    ///     </item>
    ///     <item>
    ///       要单独监听IPv4, 请设置为 '0.0.0.0'
    ///     </item>
    ///     <item>
    ///       要单独监听IPv6, 请设置为 '::'
    ///     </item>
    ///     <item>
    ///       要监听IPv4环路地址, 请设置为 '127.0.0.1'
    ///     </item>
    ///     <item>
    ///       要监听IPv6环路地址, 请设置为 '::1'
    ///     </item>
    ///   </list>
    /// </param>
    /// <param name="APort">
    ///   监听端口, 设置为0则随机监听一个可用的端口
    /// </param>
    /// <param name="ACallback">
    ///   回调匿名函数
    /// </param>
    procedure Listen(const AHost: string; const APort: Word;
      const ACallback: TCrossListenCallback = nil);

    /// <summary>
    ///   连接到主机
    /// </summary>
    /// <param name="AHost">
    ///   主机地址
    /// </param>
    /// <param name="APort">
    ///   主机端口
    /// </param>
    /// <param name="ACallback">
    ///   回调匿名函数
    /// </param>
    procedure Connect(const AHost: string; const APort: Word;
      const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   发送数据
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    /// <param name="ABuf">
    ///   数据指针
    /// </param>
    /// <param name="ALen">
    ///   数据尺寸
    /// </param>
    /// <param name="ACallback">
    ///   回调匿名函数
    /// </param>
    /// <remarks>
    ///   由于发送是异步的, 所以需要调用者保证发送完成之前数据的有效性
    /// </remarks>
    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil);

    /// <summary>
    ///   关闭所有连接
    /// </summary>
    /// <remarks>
    ///   正在发送中的数据将会丢失
    /// </remarks>
    procedure CloseAllConnections;

    /// <summary>
    ///   关闭所有监听
    /// </summary>
    procedure CloseAllListens;

    /// <summary>
    ///   关闭所有监听及连接
    /// </summary>
    procedure CloseAll;

    /// <summary>
    ///   断开所有连接
    /// </summary>
    /// <remarks>
    ///   正在发送中的数据会被送达
    /// </remarks>
    procedure DisconnectAll;

    /// <summary>
    ///   加锁并返回所有连接
    /// </summary>
    function LockConnections: TCrossConnections;

    /// <summary>
    ///   解锁连接
    /// </summary>
    procedure UnlockConnections;

    /// <summary>
    ///   加锁并返回所有监听
    /// </summary>
    function LockListens: TCrossListens;

    /// <summary>
    ///   解锁监听
    /// </summary>
    procedure UnlockListens;

    /// <summary>
    ///   创建连接对象(内部使用)
    /// </summary>
    function CreateConnection(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType): ICrossConnection;

    /// <summary>
    ///   创建监听对象(内部使用)
    /// </summary>
    function CreateListen(const AOwner: ICrossSocket; const AListenSocket: THandle;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen;

    {$region '物理事件'}
    /// <summary>
    ///   监听成功后触发(内部使用)
    /// </summary>
    /// <param name="AListen">
    ///   监听对象
    /// </param>
    procedure TriggerListened(const AListen: ICrossListen);

    /// <summary>
    ///   监听结束后触发(内部使用)
    /// </summary>
    /// <param name="AListen">
    ///   监听对象
    /// </param>
    procedure TriggerListenEnd(const AListen: ICrossListen);

    /// <summary>
    ///   正在连接(内部使用)
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    procedure TriggerConnecting(const AConnection: ICrossConnection);

    /// <summary>
    ///   连接成功后触发(内部使用)
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    procedure TriggerConnected(const AConnection: ICrossConnection);

    /// <summary>
    ///   连接断开后触发(内部使用)
    /// </summary>
    /// <param name="AConnection">
    ///   连接对象
    /// </param>
    procedure TriggerDisconnected(const AConnection: ICrossConnection);
    {$endregion}

    /// <summary>
    ///   IO线程开始时触发(内部使用)
    /// </summary>
    procedure TriggerIoThreadBegin(const AIoThread: TIoEventThread);

    /// <summary>
    ///   IO线程结束时触发(内部使用)
    /// </summary>
    procedure TriggerIoThreadEnd(const AIoThread: TIoEventThread);

    /// <summary>
    ///   IO线程数
    /// </summary>
    property IoThreads: Integer read GetIoThreads;

    /// <summary>
    ///   连接数
    /// </summary>
    property ConnectionsCount: Integer read GetConnectionsCount;

    /// <summary>
    ///   监听数
    /// </summary>
    property ListensCount: Integer read GetListensCount;

    /// <summary>
    ///   IO线程开始事件
    /// </summary>
    property OnIoThreadBegin: TCrossIoThreadEvent read GetOnIoThreadBegin write SetOnIoThreadBegin;

    /// <summary>
    ///   IO线程结束事件
    /// </summary>
    property OnIoThreadEnd: TCrossIoThreadEvent read GetOnIoThreadEnd write SetOnIoThreadEnd;

    /// <summary>
    ///   监听成功事件
    /// </summary>
    property OnListened: TCrossListenEvent read GetOnListened write SetOnListened;

    /// <summary>
    ///   监听结束事件
    /// </summary>
    property OnListenEnd: TCrossListenEvent read GetOnListenEnd write SetOnListenEnd;

    /// <summary>
    ///   连接成功事件
    /// </summary>
    property OnConnected: TCrossConnectEvent read GetOnConnected write SetOnConnected;

    /// <summary>
    ///   连接断开事件
    /// </summary>
    property OnDisconnected: TCrossConnectEvent read GetOnDisconnected write SetOnDisconnected;

    /// <summary>
    ///   收到数据事件
    /// </summary>
    property OnReceived: TCrossDataEvent read GetOnReceived write SetOnReceived;

    /// <summary>
    ///   发出数据事件
    /// </summary>
    property OnSent: TCrossDataEvent read GetOnSent write SetOnSent;
  end;

  TCrossData = class abstract(TInterfacedObject, ICrossData)
  private
    class var FCrossUID: UInt64;
  private
    [unsafe]FOwner: ICrossSocket;
    FUID: UInt64;
    FSocket: THandle;
    FLocalAddr: string;
    FLocalPort: Word;
    FUserData: Pointer;
    FUserObject: TObject;
    FUserInterface: IInterface;
  protected
    function GetOwner: ICrossSocket;
    function GetUIDTag: Byte; virtual;
    function GetUID: UInt64;
    function GetSocket: THandle;
    function GetLocalAddr: string;
    function GetLocalPort: Word;
    function GetIsClosed: Boolean; virtual; abstract;
    function GetUserData: Pointer;
    function GetUserObject: TObject;
    function GetUserInterface: IInterface;

    procedure SetUserData(const AValue: Pointer);
    procedure SetUserObject(const AValue: TObject);
    procedure SetUserInterface(const AValue: IInterface);
  public
    constructor Create(const AOwner: ICrossSocket; const ASocket: THandle); virtual;
    destructor Destroy; override;

    procedure UpdateAddr; virtual;
    procedure Close; virtual; abstract;

    property Owner: ICrossSocket read GetOwner;
    property UID: UInt64 read GetUID;
    property Socket: THandle read GetSocket;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
    property UserData: Pointer read GetUserData write SetUserData;
    property UserObject: TObject read GetUserObject write SetUserObject;
    property UserInterface: IInterface read GetUserInterface write SetUserInterface;
  end;

  TAbstractCrossListen = class(TCrossData, ICrossListen)
  private
    FFamily: Integer;
    FSockType: Integer;
    FProtocol: Integer;
    FClosed: Integer;
  protected
    function GetUIDTag: Byte; override;
    function GetFamily: Integer;
    function GetSockType: Integer;
    function GetProtocol: Integer;
    function GetIsClosed: Boolean; override;
  public
    constructor Create(const AOwner: ICrossSocket; const AListenSocket: THandle;
      const AFamily, ASockType, AProtocol: Integer); reintroduce; virtual;

    procedure Close; override;

    property Owner: ICrossSocket read GetOwner;
    property Socket: THandle read GetSocket;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;
  end;

  TAbstractCrossConnection = class(TCrossData, ICrossConnection)
  public const
    SND_BUF_SIZE = 32768;
  private
    FPeerAddr: string;
    FPeerPort: Word;
    FConnectType: TConnectType;
    FConnectStatus: Integer;
  protected
    function GetUIDTag: Byte; override;
    function GetPeerAddr: string;
    function GetPeerPort: Word;
    function GetConnectType: TConnectType;
    function GetConnectStatus: TConnectStatus;
    function GetIsClosed: Boolean; override;

    function _SetConnectStatus(const AStatus: TConnectStatus): TConnectStatus; inline;
    procedure SetConnectStatus(const AValue: TConnectStatus);

    procedure DirectSend(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); virtual;
  public
    constructor Create(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType); reintroduce; virtual;

    procedure UpdateAddr; override;
    procedure Close; override;
    procedure Disconnect; virtual;

    procedure SendBuf(const ABuffer: Pointer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendBuf(const ABuffer; const ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendBytes(const ABytes: TBytes; const AOffset, ACount: Integer;
      const ACallback: TCrossConnectionCallback = nil); overload;
    procedure SendBytes(const ABytes: TBytes;
      const ACallback: TCrossConnectionCallback = nil); overload; inline;
    procedure SendStream(const AStream: TStream;
      const ACallback: TCrossConnectionCallback = nil);

    property Owner: ICrossSocket read GetOwner;
    property Socket: THandle read GetSocket;
    property LocalAddr: string read GetLocalAddr;
    property LocalPort: Word read GetLocalPort;
    property IsClosed: Boolean read GetIsClosed;

    property PeerAddr: string read GetPeerAddr;
    property PeerPort: Word read GetPeerPort;
    property ConnectType: TConnectType read GetConnectType;
    property ConnectStatus: TConnectStatus read GetConnectStatus write SetConnectStatus;
  end;

  TIoEventThread = class(TThread)
  private
    [unsafe]FCrossSocket: ICrossSocket;
  protected
    procedure Execute; override;
  public
    constructor Create(const ACrossSocket: ICrossSocket); reintroduce;
  end;

  TAbstractCrossSocket = class abstract(TInterfacedObject, ICrossSocket)
  protected const
    RCV_BUF_SIZE = 32768;
  protected class threadvar
    FRecvBuf: array [0..RCV_BUF_SIZE-1] of Byte;
  protected
    FIoThreads: Integer;

    // 设置套接字心跳参数, 用于处理异常断线(拔网线, 主机异常掉电等造成的网络异常)
    function SetKeepAlive(const ASocket: THandle): Integer;
  private
    FConnections: TCrossConnections;
    FConnectionsLock: TObject;

    FListens: TCrossListens;
    FListensLock: TObject;

    FOnIoThreadBegin: TCrossIoThreadEvent;
    FOnIoThreadEnd: TCrossIoThreadEvent;
    FOnListened: TCrossListenEvent;
    FOnListenEnd: TCrossListenEvent;
    FOnConnected: TCrossConnectEvent;
    FOnDisconnected: TCrossConnectEvent;
    FOnReceived: TCrossDataEvent;
    FOnSent: TCrossDataEvent;

    procedure _LockConnections; inline;
    procedure _UnlockConnections; inline;

    procedure _LockListens; inline;
    procedure _UnlockListens; inline;

    function GetConnectionsCount: Integer;
    function GetListensCount: Integer;

    function GetOnIoThreadBegin: TCrossIoThreadEvent;
    function GetOnIoThreadEnd: TCrossIoThreadEvent;
    function GetOnConnected: TCrossConnectEvent;
    function GetOnDisconnected: TCrossConnectEvent;
    function GetOnListened: TCrossListenEvent;
    function GetOnListenEnd: TCrossListenEvent;
    function GetOnReceived: TCrossDataEvent;
    function GetOnSent: TCrossDataEvent;

    procedure SetOnIoThreadBegin(const AValue: TCrossIoThreadEvent);
    procedure SetOnIoThreadEnd(const AValue: TCrossIoThreadEvent);
    procedure SetOnConnected(const AValue: TCrossConnectEvent);
    procedure SetOnDisconnected(const AValue: TCrossConnectEvent);
    procedure SetOnListened(const AValue: TCrossListenEvent);
    procedure SetOnListenEnd(const AValue: TCrossListenEvent);
    procedure SetOnReceived(const AValue: TCrossDataEvent);
    procedure SetOnSent(const AValue: TCrossDataEvent);
  protected
    FConnectionsCount: Integer;
    FListensCount: Integer;

    function ProcessIoEvent: Boolean; virtual; abstract;
    function GetIoThreads: Integer; virtual;

    // 创建连接对象
    function CreateConnection(const AOwner: ICrossSocket; const AClientSocket: THandle;
      const AConnectType: TConnectType): ICrossConnection; virtual; abstract;

    // 创建监听对象
    function CreateListen(const AOwner: ICrossSocket; const AListenSocket: THandle;
      const AFamily, ASockType, AProtocol: Integer): ICrossListen; virtual; abstract;

    {$region '物理事件'}
    procedure TriggerListened(const AListen: ICrossListen); virtual;
    procedure TriggerListenEnd(const AListen: ICrossListen); virtual;

    procedure TriggerConnecting(const AConnection: ICrossConnection); virtual;
    procedure TriggerConnected(const AConnection: ICrossConnection); virtual;
    procedure TriggerDisconnected(const AConnection: ICrossConnection); virtual;

    procedure TriggerReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    procedure TriggerSent(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    {$endregion}

    {$region '逻辑事件'}
    // 这几个虚方法用于在派生类中使用
    // 比如SSL中网络端口收到的是加密数据, 可能要几次接收才会收到一个完整的
    // 已加密数据包, 然后才能解密出数据, 也就是说可能几次网络端口的接收才
    // 会对应到一次实际的数据接收, 所以设计了以下接口, 以下接口是实际数据
    // 发生时才会被触发的
    procedure LogicConnected(const AConnection: ICrossConnection); virtual;
    procedure LogicDisconnected(const AConnection: ICrossConnection); virtual;
    procedure LogicReceived(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    procedure LogicSent(const AConnection: ICrossConnection; const ABuf: Pointer; const ALen: Integer); virtual;
    {$endregion}

    procedure TriggerIoThreadBegin(const AIoThread: TIoEventThread); virtual;
    procedure TriggerIoThreadEnd(const AIoThread: TIoEventThread); virtual;

    procedure StartLoop; virtual; abstract;
    procedure StopLoop; virtual; abstract;

    procedure Listen(const AHost: string; const APort: Word;
      const ACallback: TCrossListenCallback = nil); virtual; abstract;

    procedure Connect(const AHost: string; const APort: Word;
      const ACallback: TCrossConnectionCallback = nil); virtual; abstract;

    procedure Send(const AConnection: ICrossConnection; const ABuf: Pointer;
      const ALen: Integer; const ACallback: TCrossConnectionCallback = nil); virtual; abstract;

    procedure CloseAllConnections; virtual;
    procedure CloseAllListens; virtual;
    procedure CloseAll; virtual;
    procedure DisconnectAll; virtual;
  public
    constructor Create(const AIoThreads: Integer); virtual;
    destructor Destroy; override;

    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;

    function LockConnections: TCrossConnections;
    procedure UnlockConnections;

    function LockListens: TCrossListens;
    procedure UnlockListens;

    property IoThreads: Integer read GetIoThreads;
    property ConnectionsCount: Integer read GetConnectionsCount;
    property ListensCount: Integer read GetListensCount;

    property OnIoThreadBegin: TCrossIoThreadEvent read GetOnIoThreadBegin write SetOnIoThreadBegin;
    property OnIoThreadEnd: TCrossIoThreadEvent read GetOnIoThreadEnd write SetOnIoThreadEnd;
    property OnListened: TCrossListenEvent read GetOnListened write SetOnListened;
    property OnListenEnd: TCrossListenEvent read GetOnListenEnd write SetOnListenEnd;
    property OnConnected: TCrossConnectEvent read GetOnConnected write SetOnConnected;
    property OnDisconnected: TCrossConnectEvent read GetOnDisconnected write SetOnDisconnected;
    property OnReceived: TCrossDataEvent read GetOnReceived write SetOnReceived;
    property OnSent: TCrossDataEvent read GetOnSent write SetOnSent;
  end;

  function GetTagByUID(const AUID: UInt64): Byte;

  procedure _LogLastOsError(const ATag: string = '');
  procedure _Log(const S: string); overload;
  procedure _Log(const Fmt: string; const Args: array of const); overload;

implementation

uses
  Utils.Logger;

function GetTagByUID(const AUID: UInt64): Byte;
begin
  // 取最高 2 位
  Result := (AUID shr 62) and $03;
end;

procedure _Log(const S: string); overload;
begin
  if IsConsole then
    Writeln(S)
  else
    AppendLog(S);
end;

procedure _Log(const Fmt: string; const Args: array of const); overload;
begin
  _Log(Format(Fmt, Args));
end;

procedure _LogLastOsError(const ATag: string);
{$IFDEF __DEBUG__}
var
  LError: Integer;
  LErrMsg: string;
{$ENDIF}
begin
  {$IFDEF __DEBUG__}
  LError := GetLastError;
  if (ATag <> '') then
    LErrMsg := ATag + ' : '
  else
    LErrMsg := '';
  LErrMsg := LErrMsg + Format('System Error.  Code: %0:d(%0:.4x), %1:s',
    [LError, SysErrorMessage(LError)]);
  _Log(LErrMsg);
  {$ENDIF}
end;

{ TIoEventThread }

constructor TIoEventThread.Create(const ACrossSocket: ICrossSocket);
begin
  inherited Create(True);
  FCrossSocket := ACrossSocket;
  Suspended := False;
end;

procedure TIoEventThread.Execute;
var
  {$IFDEF __DEBUG__}
  LRunCount: Int64;
  {$ENDIF}
  LCrossSocketObj: TAbstractCrossSocket;
begin
  LCrossSocketObj := FCrossSocket as TAbstractCrossSocket;
  try
    LCrossSocketObj.TriggerIoThreadBegin(Self);
    {$IFDEF __DEBUG__}
    LRunCount := 0;
    {$ENDIF}
    while not Terminated do
    begin
      try
        if not LCrossSocketObj.ProcessIoEvent then Break;
      except
        {$IFDEF __DEBUG__}
        on e: Exception do
          _Log('%s Io线程ID %d, 异常 %s, %s', [LCrossSocketObj.ClassName, Self.ThreadID, e.ClassName, e.Message]);
        {$ENDIF}
      end;
      {$IFDEF __DEBUG__}
      Inc(LRunCount)
      {$ENDIF};
    end;
    {$IFDEF __DEBUG__}
  //  _Log('%s Io线程ID %d, 被调用了 %d 次', [LCrossSocketObj.ClassName, Self.ThreadID, LRunCount]);
    {$ENDIF}
  finally
    LCrossSocketObj.TriggerIoThreadEnd(Self);
  end;
end;

{ TAbstractCrossSocket }

procedure TAbstractCrossSocket.CloseAll;
begin
  CloseAllListens;
  CloseAllConnections;
end;

procedure TAbstractCrossSocket.CloseAllConnections;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  _LockConnections;
  try
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    LConnection.Close;
end;

procedure TAbstractCrossSocket.CloseAllListens;
var
  LListenArr: TArray<ICrossListen>;
  LListen: ICrossListen;
begin
  _LockListens;
  try
    LListenArr := FListens.Values.ToArray;
  finally
    _UnlockListens;
  end;

  for LListen in LListenArr do
    LListen.Close;
end;

constructor TAbstractCrossSocket.Create(const AIoThreads: Integer);
begin
  FIoThreads := AIoThreads;

  FListens := TCrossListens.Create;
  FListensLock := TObject.Create;

  FConnections := TCrossConnections.Create;
  FConnectionsLock := TObject.Create;
end;

destructor TAbstractCrossSocket.Destroy;
begin
  FreeAndNil(FListens);
  FreeAndNil(FListensLock);

  FreeAndNil(FConnections);
  FreeAndNil(FConnectionsLock);

  inherited;
end;

procedure TAbstractCrossSocket.DisconnectAll;
var
  LLConnectionArr: TArray<ICrossConnection>;
  LConnection: ICrossConnection;
begin
  _LockConnections;
  try
    LLConnectionArr := FConnections.Values.ToArray;
  finally
    _UnlockConnections;
  end;

  for LConnection in LLConnectionArr do
    LConnection.Disconnect;
end;

procedure TAbstractCrossSocket.AfterConstruction;
begin
  StartLoop;
  inherited AfterConstruction;
end;

procedure TAbstractCrossSocket.BeforeDestruction;
begin
  StopLoop;
  inherited BeforeDestruction;
end;

function TAbstractCrossSocket.GetConnectionsCount: Integer;
begin
  Result := FConnectionsCount;
end;

function TAbstractCrossSocket.GetIoThreads: Integer;
begin
  if (FIoThreads > 0) then
    Result := FIoThreads
  else
    Result := CPUCount * 2 + 1;
end;

function TAbstractCrossSocket.GetListensCount: Integer;
begin
  Result := FListensCount;
end;

function TAbstractCrossSocket.GetOnConnected: TCrossConnectEvent;
begin
  Result := FOnConnected;
end;

function TAbstractCrossSocket.GetOnDisconnected: TCrossConnectEvent;
begin
  Result := FOnDisconnected;
end;

function TAbstractCrossSocket.GetOnIoThreadBegin: TCrossIoThreadEvent;
begin
  Result := FOnIoThreadBegin;
end;

function TAbstractCrossSocket.GetOnIoThreadEnd: TCrossIoThreadEvent;
begin
  Result := FOnIoThreadEnd;
end;

function TAbstractCrossSocket.GetOnListened: TCrossListenEvent;
begin
  Result := FOnListened;
end;

function TAbstractCrossSocket.GetOnListenEnd: TCrossListenEvent;
begin
  Result := FOnListenEnd;
end;

function TAbstractCrossSocket.GetOnReceived: TCrossDataEvent;
begin
  Result := FOnReceived;
end;

function TAbstractCrossSocket.GetOnSent: TCrossDataEvent;
begin
  Result := FOnSent;
end;

function TAbstractCrossSocket.LockConnections: TCrossConnections;
begin
  _LockConnections;
  Result := FConnections;
end;

function TAbstractCrossSocket.LockListens: TCrossListens;
begin
  _LockListens;
  Result := FListens;
end;

procedure TAbstractCrossSocket.LogicConnected(const AConnection: ICrossConnection);
begin

end;

procedure TAbstractCrossSocket.LogicDisconnected(const AConnection: ICrossConnection);
begin

end;

procedure TAbstractCrossSocket.LogicReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin

end;

procedure TAbstractCrossSocket.LogicSent(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin

end;

function TAbstractCrossSocket.SetKeepAlive(const ASocket: THandle): Integer;
begin
  Result := TSocketAPI.SetKeepAlive(ASocket, 5, 3, 5);
end;

procedure TAbstractCrossSocket.SetOnConnected(const AValue: TCrossConnectEvent);
begin
  FOnConnected := AValue;
end;

procedure TAbstractCrossSocket.SetOnDisconnected(const AValue: TCrossConnectEvent);
begin
  FOnDisconnected := AValue;
end;

procedure TAbstractCrossSocket.SetOnIoThreadBegin(
  const AValue: TCrossIoThreadEvent);
begin
  FOnIoThreadBegin := AValue;
end;

procedure TAbstractCrossSocket.SetOnIoThreadEnd(
  const AValue: TCrossIoThreadEvent);
begin
  FOnIoThreadEnd := AValue;
end;

procedure TAbstractCrossSocket.SetOnListened(const AValue: TCrossListenEvent);
begin
  FOnListened := AValue;
end;

procedure TAbstractCrossSocket.SetOnListenEnd(const AValue: TCrossListenEvent);
begin
  FOnListenEnd := AValue;
end;

procedure TAbstractCrossSocket.SetOnReceived(const AValue: TCrossDataEvent);
begin
  FOnReceived := AValue;
end;

procedure TAbstractCrossSocket.SetOnSent(const AValue: TCrossDataEvent);
begin
  FOnSent := AValue;
end;

procedure TAbstractCrossSocket.TriggerConnecting(const AConnection: ICrossConnection);
begin
  AConnection.ConnectStatus := csConnecting;

  _LockConnections;
  try
    FConnections.AddOrSetValue(AConnection.UID, AConnection);
    FConnectionsCount := FConnections.Count;
  finally
    _UnlockConnections;
  end;
end;

procedure TAbstractCrossSocket.TriggerConnected(const AConnection: ICrossConnection);
begin
  AConnection.UpdateAddr;
  AConnection.ConnectStatus := csConnected;

  LogicConnected(AConnection);

  if Assigned(FOnConnected) then
    FOnConnected(Self, AConnection);
end;

procedure TAbstractCrossSocket.TriggerDisconnected(const AConnection: ICrossConnection);
begin
  AConnection.ConnectStatus := csClosed;

  _LockConnections;
  try
    FConnections.Remove(AConnection.UID);
    FConnectionsCount := FConnections.Count;
  finally
    _UnlockConnections;
  end;

  LogicDisconnected(AConnection);

  if Assigned(FOnDisconnected) then
    FOnDisconnected(Self, AConnection);
end;

procedure TAbstractCrossSocket.TriggerIoThreadBegin(const AIoThread: TIoEventThread);
begin
  if Assigned(FOnIoThreadBegin) then
    FOnIoThreadBegin(Self, AIoThread);
end;

procedure TAbstractCrossSocket.TriggerIoThreadEnd(const AIoThread: TIoEventThread);
begin
  if Assigned(FOnIoThreadEnd) then
    FOnIoThreadEnd(Self, AIoThread);
end;

procedure TAbstractCrossSocket.TriggerListened(const AListen: ICrossListen);
begin
  AListen.UpdateAddr;

  _LockListens;
  try
    FListens.AddOrSetValue(AListen.UID, AListen);
    FListensCount := FListens.Count;
  finally
    _UnlockListens;
  end;

  if Assigned(FOnListened) then
    FOnListened(Self, AListen);
end;

procedure TAbstractCrossSocket.TriggerListenEnd(const AListen: ICrossListen);
begin
  _LockListens;
  try
    FListens.Remove(AListen.UID);
    FListensCount := FListens.Count;
  finally
    _UnlockListens;
  end;

  if Assigned(FOnListenEnd) then
    FOnListenEnd(Self, AListen);
end;

procedure TAbstractCrossSocket.TriggerReceived(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  LogicReceived(AConnection, ABuf, ALen);

  if Assigned(FOnReceived) then
    FOnReceived(Self, AConnection, ABuf, ALen);
end;

procedure TAbstractCrossSocket.TriggerSent(const AConnection: ICrossConnection;
  const ABuf: Pointer; const ALen: Integer);
begin
  LogicSent(AConnection, ABuf, ALen);

  if Assigned(FOnSent) then
    FOnSent(Self, AConnection, ABuf, ALen);
end;

procedure TAbstractCrossSocket.UnlockConnections;
begin
  _UnlockConnections;
end;

procedure TAbstractCrossSocket.UnlockListens;
begin
  _UnlockListens;
end;

procedure TAbstractCrossSocket._LockConnections;
begin
  System.TMonitor.Enter(FConnectionsLock);
end;

procedure TAbstractCrossSocket._LockListens;
begin
  System.TMonitor.Enter(FListensLock);
end;

procedure TAbstractCrossSocket._UnlockConnections;
begin
  System.TMonitor.Exit(FConnectionsLock);
end;

procedure TAbstractCrossSocket._UnlockListens;
begin
  System.TMonitor.Exit(FListensLock);
end;

{ TCrossData }

constructor TCrossData.Create(const AOwner: ICrossSocket; const ASocket: THandle);
begin
  // 理论上说62位的唯一编号永远也不可能用完
  // 所以也就不用考虑编号重置的问题了
  FUID :=
    // 高2位 标志位
    (UInt64(GetUIDTag and $03) shl 62) or
    // 低62位 编号位
    (UID_MASK and AtomicIncrement(FCrossUID));

  FOwner := AOwner;
  FSocket := ASocket;
end;

destructor TCrossData.Destroy;
begin
  if (FSocket <> INVALID_HANDLE_VALUE) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    {$IFDEF __DEBUG__}
//    _Log('close result %d', [GetLastError]);
    {$ENDIF}
    FSocket := INVALID_HANDLE_VALUE;
  end;

  inherited;
end;

function TCrossData.GetLocalAddr: string;
begin
  Result := FLocalAddr;
end;

function TCrossData.GetLocalPort: Word;
begin
  Result := FLocalPort;
end;

function TCrossData.GetOwner: ICrossSocket;
begin
  Result := FOwner;
end;

function TCrossData.GetSocket: THandle;
begin
  Result := FSocket;
end;

function TCrossData.GetUID: UInt64;
begin
  Result := FUID;
end;

function TCrossData.GetUIDTag: Byte;
begin
  Result := UID_RAW;
end;

function TCrossData.GetUserData: Pointer;
begin
  Result := FUserData;
end;

function TCrossData.GetUserInterface: IInterface;
begin
  Result := FUserInterface;
end;

function TCrossData.GetUserObject: TObject;
begin
  Result := FUserObject;
end;

procedure TCrossData.SetUserData(const AValue: Pointer);
begin
  FUserData := AValue;
end;

procedure TCrossData.SetUserInterface(const AValue: IInterface);
begin
  FUserInterface := AValue;
end;

procedure TCrossData.SetUserObject(const AValue: TObject);
begin
  FUserObject := AValue;
end;

procedure TCrossData.UpdateAddr;
var
  LAddr: TRawSockAddrIn;
begin
  {$region '本地地址信息'}
  FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
  LAddr.AddrLen := SizeOf(LAddr.Addr6);
  if (TSocketAPI.GetSockName(FSocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
    TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen,
      FLocalAddr, FLocalPort);
  {$endregion}
end;

{ TAbstractCrossListen }

constructor TAbstractCrossListen.Create(const AOwner: ICrossSocket;
  const AListenSocket: THandle; const AFamily, ASockType, AProtocol: Integer);
begin
  inherited Create(AOwner, AListenSocket);

  FFamily := AFamily;
  FSockType := ASockType;
  FProtocol := AProtocol;

  FClosed := 0;
end;

procedure TAbstractCrossListen.Close;
begin
  if (AtomicExchange(FClosed, 1) = 1) then Exit;

  if (FSocket <> INVALID_HANDLE_VALUE) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    FOwner.TriggerListenEnd(Self);
    FSocket := INVALID_HANDLE_VALUE;
  end;
end;

function TAbstractCrossListen.GetFamily: Integer;
begin
  Result := FFamily;
end;

function TAbstractCrossListen.GetIsClosed: Boolean;
begin
  Result := (FClosed = 1);
end;

function TAbstractCrossListen.GetProtocol: Integer;
begin
  Result := FProtocol;
end;

function TAbstractCrossListen.GetSockType: Integer;
begin
  Result := FSockType;
end;

function TAbstractCrossListen.GetUIDTag: Byte;
begin
  Result := UID_LISTEN;
end;

{ TAbstractCrossConnection }

constructor TAbstractCrossConnection.Create(const AOwner: ICrossSocket;
  const AClientSocket: THandle; const AConnectType: TConnectType);
begin
  inherited Create(AOwner, AClientSocket);

  FConnectType := AConnectType;
end;

procedure TAbstractCrossConnection.SetConnectStatus(const AValue: TConnectStatus);
begin
  _SetConnectStatus(AValue);
end;

procedure TAbstractCrossConnection.Close;
begin
  if (_SetConnectStatus(csClosed) = csClosed) then Exit;

  if (FSocket <> INVALID_HANDLE_VALUE) then
  begin
    TSocketAPI.CloseSocket(FSocket);
    FOwner.TriggerDisconnected(Self);
    FSocket := INVALID_HANDLE_VALUE;
  end;
end;

procedure TAbstractCrossConnection.DirectSend(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LBuffer: Pointer;
begin
  if (FSocket = INVALID_HANDLE_VALUE)
    or IsClosed then
  begin
    if Assigned(ACallback) then
      ACallback(Self, False);
    Exit;
  end;

  LBuffer := ABuffer;
  FOwner.Send(Self, LBuffer, ACount,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      if ASuccess then
        (FOwner as TAbstractCrossSocket).TriggerSent(AConnection, LBuffer, ACount);

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TAbstractCrossConnection.Disconnect;
begin
  if (_SetConnectStatus(csDisconnected) in [csDisconnected, csClosed]) then Exit;

  TSocketAPI.Shutdown(FSocket, 2);
end;

function TAbstractCrossConnection.GetConnectStatus: TConnectStatus;
begin
  Result := TConnectStatus(AtomicCmpExchange(FConnectStatus, 0, 0));
end;

function TAbstractCrossConnection.GetConnectType: TConnectType;
begin
  Result := FConnectType;
end;

function TAbstractCrossConnection.GetIsClosed: Boolean;
begin
  Result := (GetConnectStatus = csClosed);
end;

function TAbstractCrossConnection.GetPeerAddr: string;
begin
  Result := FPeerAddr;
end;

function TAbstractCrossConnection.GetPeerPort: Word;
begin
  Result := FPeerPort;
end;

function TAbstractCrossConnection.GetUIDTag: Byte;
begin
  Result := UID_CONNECTION;
end;

procedure TAbstractCrossConnection.SendBuf(const ABuffer: Pointer;
  const ACount: Integer; const ACallback: TCrossConnectionCallback);
{$IF defined(POSIX) or not defined(__LITTLE_PIECE__)}
begin
  DirectSend(ABuffer, ACount, ACallback);
end;
{$ELSE} // MSWINDOWS
// Windows下 iocp 发送数据会锁定非页面内存, 为了减少非页面内存的占用
// 采用将大数据分小块发送的策略, 一个小块发送完之后再发送下一个
var
  P: PByte;
  LSize: Integer;
  LSender: TCrossConnectionCallback;
begin
  P := ABuffer;
  LSize := ACount;

  LSender :=
    procedure(AConnection: ICrossConnection; ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: Integer;
    begin
      if not ASuccess then
      begin
        LSender := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, False);

        AConnection.Close;

        Exit;
      end;

      LData := P;
      LCount := Min(LSize, SND_BUF_SIZE);

      if (LSize > LCount) then
      begin
        Inc(P, LCount);
        Dec(LSize, LCount);
      end else
      begin
        LSize := 0;
        P := nil;
      end;

      if (LData = nil) or (LCount <= 0) then
      begin
        LSender := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, True);

        Exit;
      end;

      TAbstractCrossConnection(AConnection).DirectSend(LData, LCount, LSender);
    end;

  LSender(Self, True);
end;
{$ENDIF}

procedure TAbstractCrossConnection.SendBuf(const ABuffer; const ACount: Integer;
  const ACallback: TCrossConnectionCallback);
begin
  SendBuf(@ABuffer, ACount, ACallback);
end;

procedure TAbstractCrossConnection.SendBytes(const ABytes: TBytes;
  const AOffset, ACount: Integer; const ACallback: TCrossConnectionCallback);
var
  LBytes: TBytes;
begin
  // 增加引用计数
  // 由于 SendBuf 的 ABuffer 参数是直接传递的内存地址
  // 所以并不会增加 ABytes 的引用计数, 这里为了保证发送过程中数据的有效性
  // 需要定义一个局部变量用来引用 ABytes, 以维持其引用计数
  LBytes := ABytes;
  SendBuf(@LBytes[AOffset], ACount,
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    begin
      // 减少引用计数
      LBytes := nil;

      if Assigned(ACallback) then
        ACallback(AConnection, ASuccess);
    end);
end;

procedure TAbstractCrossConnection.SendBytes(const ABytes: TBytes;
  const ACallback: TCrossConnectionCallback);
begin
  SendBytes(ABytes, 0, Length(ABytes), ACallback);
end;

procedure TAbstractCrossConnection.SendStream(const AStream: TStream;
  const ACallback: TCrossConnectionCallback);
var
  LBuffer: TBytes;
  LSender: TCrossConnectionCallback;
begin
  if (AStream is TBytesStream) then
  begin
    SendBytes(
      TBytesStream(AStream).Bytes,
      TBytesStream(AStream).Position,
      TBytesStream(AStream).Size - TBytesStream(AStream).Position,
      ACallback);
    Exit;
  end;

  SetLength(LBuffer, SND_BUF_SIZE);

  LSender :=
    procedure(const AConnection: ICrossConnection; const ASuccess: Boolean)
    var
      LData: Pointer;
      LCount: Integer;
    begin
      if not ASuccess then
      begin
        LSender := nil;
        LBuffer := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, False);

        AConnection.Close;

        Exit;
      end;

      LData := @LBuffer[0];
      LCount := AStream.Read(LBuffer[0], SND_BUF_SIZE);

      if (LData = nil) or (LCount <= 0) then
      begin
        LSender := nil;
        LBuffer := nil;

        if Assigned(ACallback) then
          ACallback(AConnection, True);

        Exit;
      end;

      TAbstractCrossConnection(AConnection).DirectSend(LData, LCount, LSender);
    end;

  LSender(Self, True);
end;

procedure TAbstractCrossConnection.UpdateAddr;
var
  LAddr: TRawSockAddrIn;
begin
  inherited;

  {$region '远端地址信息'}
  FillChar(LAddr, SizeOf(TRawSockAddrIn), 0);
  LAddr.AddrLen := SizeOf(LAddr.Addr6);
  if (TSocketAPI.GetPeerName(FSocket, @LAddr.Addr, LAddr.AddrLen) = 0) then
    TSocketAPI.ExtractAddrInfo(@LAddr.Addr, LAddr.AddrLen, FPeerAddr, FPeerPort);
  {$endregion}
end;

function TAbstractCrossConnection._SetConnectStatus(
  const AStatus: TConnectStatus): TConnectStatus;
begin
  Result := TConnectStatus(AtomicExchange(FConnectStatus, Integer(AStatus)));
end;

end.
