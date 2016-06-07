def clean_html?
  false
end

format :html do
  view :core do
    warnings = []
    if Card.config.action_mailer.perform_deliveries == false
      warnings << email_warning
    end
    if Card.config.recaptcha_public_key ==
       Card::Auth::DEFAULT_RECAPTCHA_SETTINGS[:recaptcha_public_key] &&
       card.rule(:captcha) == '1'
      warnings << recaptcha_warning
    end
    return '' if warnings.empty?
    alert :warning, dismissible: true do
      render_warning_list warnings
    end
  end

  def render_warning_list warnings
    '<h6>ADMINISTRATOR WARNING</h6>'.html_safe + list_tag(
      warnings,
      class: 'list-group',
      items: {
        class: 'list-group-item list-group-item-warning'
      }
    )
  end

  def email_warning
    %(
      Email delivery is turned off.
      Change settings in config/application.rb to send sign up notifications.
    )
  end

  def recaptcha_warning
    warning =
      if Card::Env.localhost?
        %(Your captcha is currently working with temporary settings. This is fine for a local installation, but you will need new recaptcha keys if you want to make this site public.)
      else
        process_content(%(You are configured to use [[*captcha]], but for that to work you need new recaptcha keys.
          ))
      end
    <<-HTML
      <p>
        #{warning}
      </p>
      <h4>Instructions</h4>
      #{howto_add_new_recaptcha_keys}
      #{howto_turn_captcha_off}
    HTML
  end

  def instructions title, steps
    steps = list_tag steps, class: 'list-group',
                            items: { class: 'list-group-item' }
    "#{title}#{steps}"
  end

  def howto_add_new_recaptcha_keys
    instructions(
      'How to add new recaptcha keys:',
      [
        "1. Register your domain at  #{web_link 'http://google.com/recaptcha'}",
        "2. Add your keys to #{card_link :recaptcha_settings}"
      ]
    )
  end

  def howto_turn_captcha_off
    instructions(
      'How to turn captcha off:',
      [
        "1. Go to #{card_link :captcha}",
        '2. Update all *captcha rules to "no".'
      ]
    )
  end
end
