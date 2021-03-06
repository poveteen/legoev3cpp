//
//  EV3ConnectionImplObjC.mm
//  Jove's Landing
//
//  Created by David Giovannini on 1/21/15.
//  Copyright (c) 2015 Software by Jove. All rights reserved.
//

#import "SBJEV3ConnectionImplObjC.h"
#include "SBJEV3Chunk.h"

#include <thread>

using namespace SBJ::EV3;

static const std::string LogDomian = "Stream";

@interface SendPackage : NSObject
@property (nonatomic) NSData* data;
@property (atomic) bool sent;
@end

@implementation SendPackage
@end

@interface EV3ConnectionImpl()<NSStreamDelegate>
{
	std::mutex _mutex;
	std::condition_variable _isReady;
	int _openStreams;
	NSRunLoop* _runLoop;
	NSThread* _thread;
	Connection::Read _read;
	Log* _log;
}

@end

@implementation EV3ConnectionImpl

- (id) init: (Log&) log
{
	self = [super init];
	_log = &log;
	return self;
}

- (void) dealloc
{
	[self closeWithError: nil];
}

- (void) closeWithError: (NSError*) error
{
	[self closeStream: self.inputStream];
	[self closeStream: self.outputStream];
	_thread = nil;
	_runLoop = nil;
}

- (void) closeStream: (NSStream*) stream
{
	[stream close];
	[stream removeFromRunLoop: _runLoop forMode: NSDefaultRunLoopMode];
	stream.delegate = nil;
}

- (void) start: (Connection::Read) read
{
	_read = read;
	if (_thread == nil)
	{
		_thread = [[NSThread alloc] initWithTarget: self selector: @selector(createSession) object: nil];
		_thread.qualityOfService = NSQualityOfServiceUserInteractive;
		[_thread start];
		{
			std::unique_lock<std::mutex> lock(_mutex);
			_isReady.wait_for(lock, std::chrono::milliseconds(3000), ^{return _openStreams == 3;});
		}
		_log->write(LogDomian, "Started");
	}
	else
	{
		_log->write(LogDomian, "Rebound");
	}
}

- (void) createSession
{
	_runLoop = [NSRunLoop currentRunLoop];
	_thread = [NSThread currentThread];
	
	[self createStreams];
	
	self.inputStream.delegate = self;
	[self.inputStream scheduleInRunLoop: _runLoop forMode:NSDefaultRunLoopMode];
	[self.inputStream open];
	
	self.outputStream.delegate = self;
	[self.outputStream scheduleInRunLoop: _runLoop forMode:NSDefaultRunLoopMode];
	[self.outputStream open];
	
	[_runLoop run];
}

- (void) createStreams
{
}

- (NSInputStream*) inputStream
{
	return nil;
}

- (NSOutputStream*) outputStream
{
	return nil;
}

- (bool) write: (const uint8_t*) buffer len: (size_t) len
{
	if (self.outputStream == nil) return false;
	SendPackage* package = [[SendPackage alloc] init];
	package.data = [NSData dataWithBytes: buffer length: len];
	[self performSelector: @selector(sendData:) onThread: _thread withObject: package waitUntilDone: YES modes: @[NSDefaultRunLoopMode]];
	return package.sent;
}

- (void) sendData: (SendPackage*) package
{
	NSOutputStream* stream = self.outputStream;
	const uint8_t* writing = (uint8_t*)package.data.bytes;
	size_t bytesToWrite = package.data.length;
	
	while (bytesToWrite > 0 and [stream hasSpaceAvailable])
	{
		NSInteger bytesWritten = [stream write: writing maxLength: bytesToWrite];
		if (bytesWritten == -1)
		{
			break;
		}
		bytesToWrite -= bytesWritten;
		writing += bytesWritten;
	}
	package.sent = (bytesToWrite == 0);
}

#define ExtendedLogging 0

- (void)stream:(NSStream*)theStream handleEvent:(NSStreamEvent)streamEvent
{
	bool ready = false;
	switch (streamEvent)
	{
		case NSStreamEventHasSpaceAvailable:
		{
#if ExtendedLogging
			_log->write(LogDomian, theStream.class.description, " - Space ");
#endif
			NSOutputStream* output = [self outputStream];
			if (output == theStream)
			{
				std::unique_lock<std::mutex> lock(_mutex);
				_openStreams++;
				ready = (_openStreams==3);
			}
			break;
		}
		case NSStreamEventOpenCompleted:
		{
#if ExtendedLogging
			_log->write(LogDomian, theStream.class.description, " - Open ");
#endif
			{
				std::unique_lock<std::mutex> lock(_mutex);
				_openStreams++;
				ready = (_openStreams==3);
			}
			break;
		}
		case NSStreamEventHasBytesAvailable:
		{
#if ExtendedLogging
			_log->write(LogDomian, theStream.class.description, " - Bytes ");
#endif
			NSInputStream* input = [self inputStream];
			if (input == theStream)
			{
				[self readData];
			}
			break;
		}
		case NSStreamEventEndEncountered:
		{
#if ExtendedLogging
			_log->write(LogDomian, theStream.class.description, " - End ");
#endif
			break;
		}
		case NSStreamEventErrorOccurred:
		{
			NSError* theError = [theStream streamError];
			_log->write(LogDomian, theStream.class.description, " - Error(", theError.code, ") ", theError.localizedDescription);
			[self closeWithError: theError];
			break;
		}
	}
	if (ready)
	{
		_isReady.notify_one();
	}
}

- (void) readData
{
	NSInputStream* stream = self.inputStream;
	Chunk<2048> buffer;
	while (stream.hasBytesAvailable)
	{
		NSInteger bytesRead = [stream read: buffer.writePtr() maxLength: buffer.NaturalSize];
		if (bytesRead == -1)
		{
			break;
		}
		buffer.appendSize(bytesRead);
	}
	if (_read) _read(buffer, buffer.size());
}

@end
