//
//  OCLoginController.m
//  iOCNews
//

/************************************************************************
 
 Copyright 2013-2021 Peter Hedlund peter.hedlund@me.com
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 *************************************************************************/

#import "OCLoginController.h"
#import "OCAPIClient.h"
#import "iOCNews-Swift.h"
#import "UIColor+PHColor.h"

static const NSString *rootPath = @"index.php/apps/news/api/v1-2/";

@interface OCLoginController ()

@property (strong, nonatomic) IBOutlet UILabel *connectLabel;
@property (assign) BOOL length1;
@property (assign) BOOL length2;
@property (assign) BOOL length3;

@end

@implementation OCLoginController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.serverTextField.delegate = self;
    self.usernameTextField.delegate = self;
    self.passwordTextField.delegate = self;
    self.certificateCell.accessoryView = self.certificateSwitch;
    self.length1 = NO;
    self.length2 = NO;
    self.length3 = NO;
    self.tableView.backgroundColor = UIColor.ph_popoverBackgroundColor;
    [[NSNotificationCenter defaultCenter] addObserverForName:@"ThemeUpdate" object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        self.tableView.backgroundColor = UIColor.ph_popoverBackgroundColor;
    }];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.serverTextField.text = SettingsStore.server;
    self.length1 = (self.serverTextField.text.length > 0);
    self.usernameTextField.text = SettingsStore.username;
    self.length2 = (self.usernameTextField.text.length > 0);
    self.passwordTextField.text = SettingsStore.password;
    self.length3 = (self.passwordTextField.text.length > 0);
    self.connectLabel.enabled = (self.length1 && self.length2 && self.length3);
    self.certificateSwitch.on = SettingsStore.allowUntrustedCertificate;
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        self.connectLabel.text = NSLocalizedString(@"Reconnect", @"A button title");
    } else {
        self.connectLabel.text = NSLocalizedString(@"Connect", @"A button title");
    }
}

- (IBAction)doDone:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)onCertificateSwitch:(id)sender {
    BOOL textHasChanged = (self.certificateSwitch.on != SettingsStore.allowUntrustedCertificate);
    if (textHasChanged) {
        self.connectLabel.text = NSLocalizedString(@"Connect", @"A button title");
    } else {
        self.connectLabel.text = NSLocalizedString(@"Reconnect", @"A button title");
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 44.0f;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        if (!self.connectLabel.enabled) {
            return;
        }
        [tableView deselectRowAtIndexPath:indexPath animated:true];
        
        SettingsStore.allowUntrustedCertificate = self.certificateSwitch.on;

        NSMutableString *serverInput = [NSMutableString stringWithString: self.serverTextField.text];
        if (serverInput.length > 0) {
            if ([serverInput hasSuffix:@"/"]) {
                NSUInteger lastCharIndex = serverInput.length - 1;
                NSRange rangeOfLastChar = [serverInput rangeOfComposedCharacterSequenceAtIndex: lastCharIndex];
                serverInput = [NSMutableString stringWithString: [serverInput substringToIndex: rangeOfLastChar.location]];
            }
            [self.connectionActivityIndicator startAnimating];
            OCAPIClient *client = [[OCAPIClient alloc] initWithBaseURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/%@", serverInput, rootPath]]];
            [client setRequestSerializer:[AFJSONRequestSerializer serializer]];
            [client.requestSerializer setAuthorizationHeaderFieldWithUsername:self.usernameTextField.text password:self.passwordTextField.text];
            
            [client GET:@"version" parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                NSDictionary *jsonDict = nil;
                if (responseObject && [responseObject isKindOfClass:[NSDictionary class]])
                {
                    jsonDict = (NSDictionary*)responseObject;
                }
                else
                {
                    id json = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
                    if (json && [json isKindOfClass:[NSDictionary class]]) {
                        jsonDict = (NSDictionary*)json;
                    }
                }
                if (jsonDict) {
                    NSString *version = [jsonDict valueForKey:@"version"];
                    SettingsStore.newsVersion = version;
                    SettingsStore.server = self.serverTextField.text;
                    SettingsStore.username = self.usernameTextField.text;
                    SettingsStore.password = self.passwordTextField.text;
                    SettingsStore.allowUntrustedCertificate = self.certificateSwitch.on;
                    [OCAPIClient setSharedClient:nil];
                    __unused AFNetworkReachabilityStatus status = [[OCAPIClient sharedClient].reachabilityManager networkReachabilityStatus];
                    [self.connectionActivityIndicator stopAnimating];
                    [Messenger showSyncMessageWithViewController:self];
                } else {
                    [self.connectionActivityIndicator stopAnimating];
                    [Messenger showMessageWithTitle:NSLocalizedString(@"Connection failure", @"An error message title")
                                                    body:NSLocalizedString(@"Failed to connect to a server. Check your settings.", @"An error message")
                                                   theme: MessageThemeError];
                }
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                self.connectLabel.enabled = NO;
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                NSString *message = @"";
                NSString *title = @"";
                //            NSLog(@"Status code: %ld", (long)response.statusCode);
                switch (response.statusCode) {
                    case 200:
                        title = NSLocalizedString(@"News not found", @"An error message title");
                        message = NSLocalizedString(@"News could not be found on your server. Make sure it is installed and enabled", @"An error message");
                        break;
                    case 401:
                        title = NSLocalizedString(@"Unauthorized", @"An error message title");
                        message = NSLocalizedString(@"Check username and password.", @"An error message");
                        break;
                    case 404:
                        title = NSLocalizedString(@"Server not found", @"An error message title");
                        message = NSLocalizedString(@"A server installation could not be found. Check the server address.", @"An error message");
                        break;
                    default:
                        title = NSLocalizedString(@"Connection failure", @"An error message title");
                        if (error) {
                            message = error.localizedDescription;
                        } else {
                            message = NSLocalizedString(@"Failed to connect to a server. Check your settings.", @"An error message");
                        }
                        break;
                }
                [self.connectionActivityIndicator stopAnimating];
                [Messenger showMessageWithTitle:title
                                           body:message
                                          theme:MessageThemeError];
            }];
        }
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if ([textField isEqual:self.serverTextField]) {
        [self.usernameTextField becomeFirstResponder];
    }
    if ([textField isEqual:self.usernameTextField]) {
        [self.passwordTextField becomeFirstResponder];
    }
    if ([textField isEqual:self.passwordTextField]) {
        [textField resignFirstResponder];
    }
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    NSString *labelText = @"Reconnect";
    BOOL textHasChanged = NO;

    NSMutableString *proposedNewString = [NSMutableString stringWithString:textField.text];
    [proposedNewString replaceCharactersInRange:range withString:string];
    
    if ([textField isEqual:self.serverTextField]) {
        textHasChanged = (![proposedNewString isEqualToString:SettingsStore.server]);
        self.length1 = (proposedNewString.length > 0);
    }
    if ([textField isEqual:self.usernameTextField]) {
        textHasChanged = (![proposedNewString isEqualToString:SettingsStore.username]);
        self.length2 = (proposedNewString.length > 0);
    }
    if ([textField isEqual:self.passwordTextField]) {
        textHasChanged = (![proposedNewString isEqualToString:SettingsStore.password]);
        self.length3 = (proposedNewString.length > 0);
    }
    if (!textHasChanged) {
        textHasChanged = (self.certificateSwitch.on != SettingsStore.allowUntrustedCertificate);
    }
    if (textHasChanged) {
        labelText = @"Connect";
    }
    self.connectLabel.text = labelText;
    self.connectLabel.enabled = (self.length1 && self.length2 && self.length3);
    return YES;
}

- (BOOL)textFieldShouldClear:(UITextField *)textField {
    if ([textField isEqual:self.serverTextField]) {
        self.length1 = NO;
    }
    if ([textField isEqual:self.usernameTextField]) {
        self.length2 = NO;
    }
    if ([textField isEqual:self.passwordTextField]) {
        self.length3 = NO;
    }
    self.connectLabel.enabled = NO;
    return YES;
}

@end
