//
//  RSSParser.m
//  TestRSSReader
//
//  Created by 達郎 植田 on 12/07/08.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "RSSParser.h"
#import "RSSEntry.h"

@implementation RSSParser

@synthesize entries = _entries;
@synthesize elementStack = _elementStack;
@synthesize curEntry = _curEntry;

- (id)init
{
    self = [super init];
    if (self) {
        
        // インスタンス変数の初期化
        _entries = nil;
        _elementStack = [[NSMutableArray alloc] init];
        _curEntry = nil;
    }
    return self;
}

// URLからRSSファイルを読み込む
// ここではRSS2.0のみ対応する
- (BOOL)parseContentsOfURL:(NSURL *)url progressView:(UIProgressView *)progressView
{
    _progressView = progressView;
    BOOL ret = NO;
    
    // 行数をカウントする
    NSError *error = nil;
    NSString *xmlFileString = [NSString stringWithContentsOfURL:url
                                                       encoding:NSUTF8StringEncoding
                                                          error:&error];
    _totalLines = [xmlFileString componentsSeparatedByString:@"\n"].count;
    
    // XMLパーサーの準備
    NSXMLParser *parser;
    parser = [[NSXMLParser alloc] initWithContentsOfURL:url];
    parser.delegate = self;
    
    // エントリーを入れる配列をクリアする
    self.entries = [NSMutableArray arrayWithCapacity:0];
    
    // 解析開始
    if ([parser parse]) {
        
        // アイテムが一つでも取得できていれば成功とする
        if (self.entries.count > 0) {
            ret = YES;
        }
    }
    // 中間データを削除する
    [self.elementStack removeAllObjects];
    self.curEntry = nil;
    
    return ret;
}

// エレメント開始時の処理
- (void)parser:(NSXMLParser *)parser 
didStartElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI 
 qualifiedName:(NSString *)qName 
    attributes:(NSDictionary *)attributeDict
{
    // エレメント位置を把握するためにスタックにエレメント名を追加する
    [self.elementStack addObject:elementName];
    
    // プログレスビューの更新
    // メインスレッドに戻す
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    [mainQueue addOperationWithBlock:^{
        _progressView.progress = (CGFloat)[parser lineNumber] / (CGFloat)_totalLines;
    }];
}

// エレメント終了時の処理
- (void)parser:(NSXMLParser *)parser 
 didEndElement:(NSString *)elementName 
  namespaceURI:(NSString *)namespaceURI 
 qualifiedName:(NSString *)qName
{
    // エレメント位置を把握するためのスタックからエレメント名を削除する
    [self.elementStack removeLastObject];
    
    // 終了したエレメントの名前が「item」で現在解析中のエントリーがある場合は、
    // 配列「_entries」に追加して、解放する
    if ([elementName isEqualToString:@"item"] && self.curEntry) {
        
        [self.entries addObject:_curEntry];
        self.curEntry = nil;
    }

    // プログレスビューの更新
    // メインスレッドに戻す
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    [mainQueue addOperationWithBlock:^{
        _progressView.progress = (CGFloat)[parser lineNumber] / (CGFloat)_totalLines;
    }];
}

// エレメントスタックをファイルパスのような文字列にする
- (NSString *)elementPath
{
    NSMutableString *path = [NSMutableString stringWithCapacity:0];
    
    for (NSString *str in self.elementStack) {
        
        [path appendFormat:@"/%@", str];
    }
    return path;
}

// 現在解析中のエントリーを返す
- (RSSEntry *)currentEntry
{
    if (!self.curEntry) {
        
        // まだ解析中のエントリーがないので新しく作成する
        self.curEntry = [[RSSEntry alloc] init];
    }
    return self.curEntry;
}

// 文字列が見つかったときに呼ばれる
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    // エレメント位置によってテキストノードの意味が異なる
    // 位置の判定を容易にするため、ファイルパスのような文字列にする
    NSString *str = [self elementPath];
    
    // 作成した文字列を使って判定する
    if ([str isEqualToString:@"/rss/channel/item/title"]) {
        
        // 記事のタイトル
        NSString *str = [[self currentEntry] title];
        
        if (str) {
            str = [str stringByAppendingString:string];
        }
        else {
            str = string;
        }
        [[self currentEntry] setTitle:str];
    }
    else if ([str isEqualToString:@"/rss/channel/item/link"]) {
        
        // 記事のアドレス
        NSURL *url = [NSURL URLWithString:string];
        
        
        // 該当ページのHTMLを取得する
        NSString *string = 
        [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
        
        // 検索するための正規表現を準備する
        NSError *error   = nil;
        NSRegularExpression *regexp =
        [NSRegularExpression regularExpressionWithPattern:
         @"<meta property=\"og:image\" content=\".+\""
                                                  options:0
                                                    error:&error];
        @try {
            
            // 正規表現で検索する
            NSTextCheckingResult *match =
            [regexp firstMatchInString:string options:0 range:NSMakeRange(0, string.length)];
            
            // 検索結果から最初のものを取り出す
            NSRange resultRange = [match rangeAtIndex:0];
            //NSLog(@"match=%@", [string substringWithRange:resultRange]); 
            
            if (match) {
                
                // 検索結果からog:imageのURLの部分だけを取り出す
                NSRange urlRange = NSMakeRange(resultRange.location + 35, resultRange.length - 35 - 1);
                //NSLog(@"url  =%@", [string substringWithRange:urlRange]); 
                [self currentEntry].urlOgImage = 
                [NSURL URLWithString:[string substringWithRange:urlRange]];
            }
        }
        @catch (NSException *exception) {
            [self currentEntry].urlOgImage = nil;
        }
        @finally {
        }
        
        
        
        [[self currentEntry] setUrl:url];
    }
    else if ([str isEqualToString:@"/rss/channel/item/pubDate"]) {
        
        // 記事の日時
        NSDate *date = [self pubDateWithString:string];
        [[self currentEntry] setDate:date];
    }
    else if ([str isEqualToString:@"/rss/channel/item/description"]) {
        
        // 記事の本文
        NSString *str = [[self currentEntry] text];
        
        if (str) {
            str = [str stringByAppendingString:string];
        }
        else {
            str = string;
        }
        
        [[self currentEntry] setText:str];
    }
    
    // プログレスビューの更新
    // メインスレッドに戻す
    NSOperationQueue *mainQueue = [NSOperationQueue mainQueue];
    [mainQueue addOperationWithBlock:^{
        _progressView.progress = (CGFloat)[parser lineNumber] / (CGFloat)_totalLines;
    }];
}

// RSS2.0の表記方法で書かれた日時からオブジェクトを取得する
- (NSDate *)pubDateWithString:(NSString *)string
{
    NSDate *date = nil;
    
    // スペース区切りで文字列を分割する
    NSArray *tokens = [string componentsSeparatedByString:@" "];
    
    // 区切った文字列から日時の情報を構築する
    NSDateComponents *comps = [[NSDateComponents alloc] init];
    
    // 最低限、4つ必要とする（曜日、日、月、年）
    if (tokens.count >= 4) {
        
        // タイムゾーン
        NSTimeZone *tz = [NSTimeZone localTimeZone];
        
        // 日
        [comps setDay:[[tokens objectAtIndex:1] integerValue]];
        
        // 年
        [comps setYear:[[tokens objectAtIndex:3] integerValue]];
        
        // 月を文字列から変換するため、配列を作成する
        NSArray *monthNames = [NSArray arrayWithObjects:
                               @"Jan", @"Feb", @"Mar", @"Apr",
                               @"May", @"Jun", @"Jul", @"Aug",
                               @"Sep", @"Oct", @"Nov", @"Dec", nil];
        NSInteger month = [monthNames indexOfObject:[tokens objectAtIndex:2]];
        if (month != NSNotFound) {
            
            // インデックス番号は0から始まるので、1足す
            [comps setMonth:month + 1];
            
            // 時間は「：」で区切る
            if (tokens.count > 4) {
                
                NSArray *timeTokens = [[tokens objectAtIndex:4] componentsSeparatedByString:@":"];
                
                // 時を読み込む
                if (timeTokens.count > 0) {
                    [comps setHour:[[timeTokens objectAtIndex:0] integerValue]];
                }
                
                // 分を読み込む
                if (timeTokens.count > 1) {
                    [comps setMinute:[[timeTokens objectAtIndex:1] integerValue]];
                }
                
                // 秒を読み込む
                if (timeTokens.count > 2) {
                    [comps setSecond:[[timeTokens objectAtIndex:2] integerValue]];
                }
                
                // タイムゾーンを読み込む
                if (tokens.count > 5) {
                    
                    NSString *timezoneStr = [tokens objectAtIndex:5];
                    
                    if (timezoneStr.length >= 4) {
                        
                        // うしろ4文字はオフセット値
                        // その前は符号
                        NSString *hOffset = [timezoneStr substringWithRange:
                                             NSMakeRange(timezoneStr.length - 4, 2)];
                        NSString *mOffset = [timezoneStr substringFromIndex:(timezoneStr.length - 2)];
                        NSInteger sign = 1;
                        
                        // 符号がついていれば、符号を調べる
                        if (timezoneStr.length > 4) {
                            
                            unichar uc;
                            uc = [timezoneStr characterAtIndex:(timezoneStr.length - 5)];
                            
                            if (uc == L'-') {
                                sign = -1;
                            }
                        }
                        
                        // 読み込んだ文字列からオフセット秒を計算する
                        NSInteger offsetSecond =
                        hOffset.integerValue * 3600 +
                        mOffset.integerValue * 60;
                        offsetSecond *= sign;
                        
                        // タイムゾーンを取得する
                        tz = [NSTimeZone timeZoneForSecondsFromGMT:offsetSecond];
                    }
                }
            }
            // 日付を取得する
            NSCalendar *calendar;
            calendar = [[NSCalendar alloc]
                        initWithCalendarIdentifier:NSGregorianCalendar];
            calendar.timeZone = tz;
            
            date = [calendar dateFromComponents:comps];
        }
    }
    return date;
}

@end
