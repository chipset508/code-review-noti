class SendSlackCommentService
  def self.call(comment_id)
    self.new(comment_id).call
  end

  def initialize(comment_id)
    @comment_id = comment_id
  end

  def call
    github_comment = GithubComment.find_by(id: @comment_id)
    pull_request = PullRequest.where("lower(url) = ?", github_comment.try(:pr_url).downcase).last
    return false unless github_comment
    github_comment.update(thread_ts: pull_request&.thread_ts)

    slack_comment_decorator = SlackCommentDecoratorService.new(github_comment)

    client = Slack::Web::Client.new

    if pull_request.present? && !thread_deleted?(pull_request.channel_id, pull_request.thread_ts)
      client.chat_postMessage(
        channel: pull_request.channel,
        attachments: [
          {
            color: ColorPickerService.by_state(github_comment.state),
            pretext: slack_comment_decorator.title,
            text: slack_comment_decorator.body +
              slack_comment_decorator.subscription,
            mrkdwn_in: ["pretext", "text", "fields"],
          }
        ],
        as_user: true,
        thread_ts: pull_request.thread_ts
      )
    elsif slack_comment_decorator.mentions.present?
      slack_comment_decorator.mentions.each do |mention|
        begin
          client.chat_postMessage(
            channel: mention,
            attachments: [
              {
                color: ColorPickerService.by_state(github_comment.state),
                pretext: "<#{github_comment.html_url}|:speech_balloon: #{github_comment.author_name}>",
                text: slack_comment_decorator.body,
                mrkdwn_in: ["pretext", "text", "fields"],
              }
            ],
            as_user: true
          )
        rescue
        end
      end
    end

    github_comment.update(status: true)
  end

  private

  def thread_deleted?(channel_id, thread_id)
    client = Slack::Web::Client.new
    begin

      client.conversations_replies(
        channel: channel_id,
        ts: thread_id
      )
      false
    rescue Slack::Web::Api::Errors::SlackError
      true
    end
  end
end
