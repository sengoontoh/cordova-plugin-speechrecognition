// https://developer.apple.com/library/prerelease/content/samplecode/SpeakToMe/Listings/SpeakToMe_ViewController_swift.html
// http://robusttechhouse.com/introduction-to-native-speech-recognition-for-ios/
// https://www.appcoda.com/siri-speech-framework/

#import "SpeechRecognition.h"

#import <Cordova/CDV.h>
#import <Speech/Speech.h>
#import <Accelerate/Accelerate.h>

#define DEFAULT_LANGUAGE @"en-US"
#define DEFAULT_MATCHES 5

#define MESSAGE_MISSING_PERMISSION @"Missing permission"
#define MESSAGE_ACCESS_DENIED @"User denied access to speech recognition"
#define MESSAGE_RESTRICTED @"Speech recognition restricted on this device"
#define MESSAGE_NOT_DETERMINED @"Speech recognition not determined on this device"
#define MESSAGE_ACCESS_DENIED_MICROPHONE @"User denied access to microphone"
#define MESSAGE_ONGOING @"Ongoing speech recognition"

@interface SpeechRecognition()

@property (strong, nonatomic) SFSpeechRecognizer *speechRecognizer;
@property (strong, nonatomic) AVAudioEngine *audioEngine;
@property (strong, nonatomic) SFSpeechAudioBufferRecognitionRequest *recognitionRequest;
@property (strong, nonatomic) SFSpeechRecognitionTask *recognitionTask;
@property float averagePowerForChannel0;

@end


@implementation SpeechRecognition

- (void)setupAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setActive:NO withOptions:0 error:nil];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                  withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionDuckOthers
                        error:nil];
    [audioSession setMode:AVAudioSessionModeMeasurement error:nil];
    [audioSession setActive:YES withOptions:0 error:nil];
}

- (void)deactivateAudioSession:(CDVInvokedUrlCommand*)command {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)deactivateAudioSession {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

- (void)isRecognitionAvailable:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;

    if ([SFSpeechRecognizer class]) {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
    } else {
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)startListening:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        if ( self.audioEngine.isRunning ) {
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_ONGOING];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        NSLog(@"startListening()");
        
        SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
        if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
            NSLog(@"startListening() speech recognition access not authorized");
            CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_MISSING_PERMISSION];
            [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            return;
        }
        
        [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
            if (!granted) {
                NSLog(@"startListening() microphone access not authorized");
                CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_ACCESS_DENIED_MICROPHONE];
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }
            
            NSLog(@"startListening() microphone access granted");
            
            NSString* language = [command argumentAtIndex:0 withDefault:DEFAULT_LANGUAGE];
            int matches = [[command argumentAtIndex:1 withDefault:@(DEFAULT_MATCHES)] intValue];
            BOOL showPartial = [[command argumentAtIndex:3 withDefault:@(NO)] boolValue];
            
            NSLocale *locale = [[NSLocale alloc] initWithLocaleIdentifier:language];
            self.speechRecognizer = [[SFSpeechRecognizer alloc] initWithLocale:locale];
            self.audioEngine = [[AVAudioEngine alloc] init];
            
            // Cancel the previous task if it's running.
            if ( self.recognitionTask ) {
                [self.recognitionTask cancel];
                self.recognitionTask = nil;
            }
            
            [self setupAudioSession];
            
            self.recognitionRequest = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
            self.recognitionRequest.shouldReportPartialResults = showPartial;
            
            AVAudioInputNode *inputNode = self.audioEngine.inputNode;
            AVAudioFormat *format = [inputNode outputFormatForBus:0];
            
            NSLog(@"startListening() recognitionTaskWithRequest");
            
            self.recognitionTask = [self.speechRecognizer recognitionTaskWithRequest:self.recognitionRequest resultHandler:^(SFSpeechRecognitionResult *result, NSError *error) {
                
                if ( result ) {
                    
                    NSMutableArray *resultArray = [[NSMutableArray alloc] init];
                    
                    int counter = 0;
                    for ( SFTranscription *transcription in result.transcriptions ) {
                        if (matches > 0 && counter < matches) {
                            [resultArray addObject:transcription.formattedString];
                        }
                        counter++;
                    }
                    
                    NSArray *transcriptions = [NSArray arrayWithArray:resultArray];
                    
                    NSLog(@"startListening() recognitionTask result array: %@", transcriptions.description);
                    
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:transcriptions];
                    if (showPartial){
                        [pluginResult setKeepCallbackAsBool:YES];
                    }
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
                
                if ( error ) {
                    NSLog(@"startListening() recognitionTask error: %@", error.description);
                    
                    [self.audioEngine stop];
                    [self.audioEngine.inputNode removeTapOnBus:0];
                    
                    self.recognitionRequest = nil;
                    self.recognitionTask = nil;
                    
                    [self deactivateAudioSession];
                    
                    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:error.description];
                    if (showPartial){
                        [pluginResult setKeepCallbackAsBool:YES];
                    }
                    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                }
                
                if ( result.isFinal ) {
                    NSLog(@"startListening() recognitionTask isFinal");
                    
                    [self.audioEngine stop];
                    [self.audioEngine.inputNode removeTapOnBus:0];
                    
                    self.recognitionRequest = nil;
                    self.recognitionTask = nil;
                    
                    [self deactivateAudioSession];
                }
            }];
            
            NSLog(@"startListening() installTapOnBus");
            
            [inputNode installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *when) {
                [self.recognitionRequest appendAudioPCMBuffer:buffer];
                [buffer setFrameLength:1024];
                [self audioMetering:buffer];
            }];
            
            NSLog(@"startListening() prepare");
            [self.audioEngine prepare];
            
            NSLog(@"startListening() start");
            [self.audioEngine startAndReturnError:nil];
            
            NSLog(@"startListening() finished");
        }];
    }];
}

- (void)stopListening:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        NSLog(@"stopListening()");

        if ( self.audioEngine.isRunning ) {
            [self.audioEngine stop];
            [self.recognitionRequest endAudio];
        }
        
        [self deactivateAudioSession];
        
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)getSupportedLanguages:(CDVInvokedUrlCommand*)command {
    NSSet<NSLocale *> *supportedLocales = [SFSpeechRecognizer supportedLocales];

    NSMutableArray *localesArray = [[NSMutableArray alloc] init];

    for(NSLocale *locale in supportedLocales) {
        [localesArray addObject:[locale localeIdentifier]];
    }

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:localesArray];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)hasPermission:(CDVInvokedUrlCommand*)command {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];
    BOOL speechAuthGranted = (status == SFSpeechRecognizerAuthorizationStatusAuthorized);

    if (!speechAuthGranted) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        return;
    }

    [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:granted];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)requestPermission:(CDVInvokedUrlCommand*)command {
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status){
        dispatch_async(dispatch_get_main_queue(), ^{
            CDVPluginResult *pluginResult = nil;
            BOOL speechAuthGranted = NO;

            switch (status) {
                case SFSpeechRecognizerAuthorizationStatusAuthorized:
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                    speechAuthGranted = YES;
                    break;
                case SFSpeechRecognizerAuthorizationStatusDenied:
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_ACCESS_DENIED];
                    break;
                case SFSpeechRecognizerAuthorizationStatusRestricted:
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_RESTRICTED];
                    break;
                case SFSpeechRecognizerAuthorizationStatusNotDetermined:
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_NOT_DETERMINED];
                    break;
            }

            if (!speechAuthGranted) {
                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
                return;
            }

            [[AVAudioSession sharedInstance] requestRecordPermission:^(BOOL granted){
                CDVPluginResult *pluginResult = nil;

                if (granted) {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
                } else {
                    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:MESSAGE_ACCESS_DENIED_MICROPHONE];
                }

                [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
            }];
        });
    }];
}

- (void)averagePowerForChannel0:(CDVInvokedUrlCommand*)command {
    CDVPluginResult *pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDouble:self.averagePowerForChannel0];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)audioMetering:(AVAudioPCMBuffer*)buffer {
    UInt32 inNumberFrames = buffer.frameLength;
    if (buffer.format.channelCount > 0) {
        Float32* samples = (Float32*)buffer.floatChannelData[0];
        Float32 avgValue = 0;
        vDSP_meamgv((Float32*)samples, 1, &avgValue, inNumberFrames);
        double value = avgValue != 0 ? log10f(avgValue) * 20 : 0;
        self.averagePowerForChannel0 = value;
    }
}

@end
