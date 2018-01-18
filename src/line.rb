require './src/event/postback'
require './src/start'
def client
  @client ||= Line::Bot::Client.new { |config|

    config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
    config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
  }
end

post '/callback' do
  body = request.body.read

  signature = request.env['HTTP_X_LINE_SIGNATURE']
  unless client.validate_signature(body, signature)
    error 400 do 'Bad Request' end
  end

  events = client.parse_events_from(body)
  events.each do |event|
    case event
    when Line::Bot::Event::Message
      case event.type
      when Line::Bot::Event::MessageType::Text
        msg = nil

        room = Room.where(channel_id: event["source"]["userId"])[0]
        if room.nil?
          get_id(event["source"])
          room  = Room.where(channel_id: channel_id)[0]
        end

        if not room
          m = MessageButton.new('学科選択中')
          m.pushButton('医学科',   {"data": "type=dept&department=igaku"})
          m.pushButton('看護学科', {"data": "type=dept&department=kango"})
          client.reply_message(event['replyToken'], m.reply('学科選択', '情報を登録してね！'))
        end
        dept  = room["department"]
        grade = room["grade"]

        if (event.message['text'] =~ /何時まで/ or event.message['text'] =~ /終了時間/)
          t = getDate(event.message['text'])
          if t.nil?
            msg = '日付が見つかりませんでした。'
          else
            msg = getEndTime(dept, grade, t.month, t.day)
          end
        # bus
        elsif event.message['text'] =~ /バス/
            m = MessageConfirm.new('バス出発地点洗濯中')
            m.pushButton('瀬田駅',   {"data": "type=bus&pin=seta"})
            m.pushButton('医大西門', {"data": "type=bus&pin=idai"})
            client.reply_message(event['replyToken'], m.reply("バス時刻表\nどこから出発しますか？"))
        # update
        elsif event.message['text'] =~ /アップデート/
          if Exam.last.updated_at.yday != Time.now.yday
            m = MessageConfirm.new('時間割アップデート確認')
            m.pushButton('はい',   {"data": "type=update&status=true",  "text": "アップデートして！"})
            m.pushButton('いいえ', {"data": "type=update&status=false"})
            client.reply_message(event['replyToken'], m.reply("時間割アップデート確認\n本当にアップデートしますか？"))
          else
            client.reply_message(event['replyToken'], { type: 'text', text: 'アップデートできないです' })
          end
        elsif event.message['text'] == "アップデートして！"
          client.reply_message(event['replyToken'], { type: 'text', text: 'アップデートを開始します' })
        elsif (event.message['text'] =~ /授業/ or event.message['text'] =~ /時間/)
          t = getDate(event.message['text'])
          if t.nil?
            msg = '日付が見つかりませんでした。'
          else
            msg = op(dept, grade, t.month, t.day)
          end
        elsif (event.message['text'] =~ /試験/ or event.message['text'] =~ /テスト/) and event.message['text'] =~ /(\d{1,2})\/(\d{1,2})/
          begin
            m = event.message['text'].match(/(\d{1,2})\/(\d{1,2})/)
            t = Time.parse("#{t.year}/#{m[1]}/#{m[2]}")
            msg = getExams(dept, grade, t.month, t.day)
          rescue => e
            msg = '日付の入力を直してください 月/日'
          end
        elsif (event.message['text'] =~ /試験/ or event.message['text'] =~ /テスト/) and event.message['text'] =~ /の/
          begin
            title = event.message['text'].split('の')[0]
            msg = getExamsTitle(dept, grade, title)
          rescue => e
            msg = 'その教科はありません'
          end
        elsif event.message['text'] =~ /カンカン/ and event.message['text'] =~ /設定/
          m = MessageButton.new('学科選択中')
          m.pushButton('医学科',   {"data": "type=dept&department=igaku"})
          m.pushButton('看護学科', {"data": "type=dept&department=kango"})
          client.reply_message(event['replyToken'], m.reply('学科選択', '設定を変更する？学科を教えてね！'))
        elsif event.message['text'] =~ /カンカン/ and (event.message['text'] =~ /ヘルプ/ or event.message['text'] =~ /help/)
          content = [
            "\u{1F4AC}[今日,曜日,日付(月/日)]の授業は？",
            "　\u{2705} 時間割を教えるよ！",
            "\u{1F4AC}[科目(略称可)]のテストは？",
            "　\u{2705} 試験を教えるよ！",
            "\u{1F4AC}[日付(月/日)]のテストは？",
            "　\u{2705} 2週間以内の試験を教えるよ！",
            "\u{1F4AC}[今日,曜日,日付(月/日)]何時まで？",
            "　\u{2705} 終わりの時間を教えてくれるよ！",
            "\u{1F4AC}カンカン設定！",
            "　\u{2705} 学科,学年を変更できるよ！",
            "\u{1F4AC}カンカンヘルプ！",
            "　\u{2705} 指示の一覧が見れるよ！"]
          msg = content.join("\n")
        end
        if not msg.nil?
          message = {
            type: 'text',
            text: msg
          }
          client.reply_message(event['replyToken'], message)
        end
      end
    when Line::Bot::Event::Join
      client.reply_message(event['replyToken'], startAction)
    when Line::Bot::Event::Follow
      client.reply_message(event['replyToken'], startAction)
    when Line::Bot::Event::Postback
      Actionpostback(event)
    end
  end

  "OK"
end