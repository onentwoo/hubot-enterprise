# Notes:
#  Copyright 2016 Hewlett-Packard Development Company, L.P.
#
#  Permission is hereby granted, free of charge, to any person obtaining a
#  copy of this software and associated documentation files (the "Software"),
#  to deal in the Software without restriction, including without limitation
#  the rights to use, copy, modify, merge, publish, distribute, sublicense,
#  and/or sell copie of the Software, and to permit persons to whom the
#  Software is furnished to do so, subject to the following conditions:
#
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
#
#  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#  SOFTWARE.


# admin actions for flowdock

request = require 'request'
Promise = require 'bluebird'
Channel = require './libs/channel'
Querystring = require 'querystring'
User = require './libs/user'
_ = require 'lodash'
class Adapter
  constructor: (apiToken = process.env.HUBOT_FLOWDOCK_API_TOKEN) ->
    @apiToken = apiToken

  # multiline quotation method for platform
  quote:
    start: "\n```\n"
    end: '```'

  callAPI: (command, type, options) ->
    api_url = "https://#{@apiToken}@api.flowdock.com/"
    options = options||{}
    new Promise (resolve, reject)->
      request[type](api_url + command, form: options,
      (err, reponse, body)->
        if not err and reponse.statusCode == 200
          json = JSON.parse(body)
          reject(json.message) unless !json.message
          resolve(json)
        else
          reject(err)
      )

  # get info for specific channel
  #
  # channelId: id or name of the channel
  #
  # returns Channel object
  # throws Promise rejection
  channelInfo: (channelId) ->
    # TODO: channelNameToId
    return @callAPI('flows/find', 'get', {id: channelId})
    .then (channel) ->
      return new Channel(channel.id, channel.parameterized_name, channel.name,
        channel.sources[0].created_at, channel.description)

  # list channels
  #
  # excludeArchived: exclude archived channels
  #
  # returns array of Channel objects
  # throws Promise rejection
  channelList: (excludeArchived) ->
    # TODO: implement excludeArchived
    _this = @
    return @callAPI('flows', 'get')
    .then (channels) ->
      return Promise.map(channels, (channel) ->
        return _this.channelInfo(channel.id)
      )
      .then (channels) ->
        return channels

  # get list of users
  #
  # returns array of User objects
  usersList: () ->
    ret = []
    return @callAPI('users', 'get')
    .then (users) ->
      for user in users
        fullName = user.name.split(' ')
        ret.push(new User(user.id, user.nick, user.email,
          fullName[0] || '', fullName[1] || ''))
      return ret

  # find channel/s, return id array
  #
  # channels: array of channels or string: accepting name, nice_name, id
  #
  # returns array of user ids
  findChannels: (channels) ->
    res = []
    if (typeof channels == 'string')
      channels = [channels]
    return @channelList()
    .then (channelList) ->
      console.log(channelList)
      for channel in channelList
        if (_.includes(channels, channel.id))
          channels.splice(channels.indexOf(channel.id), 1)
          res.push(channel.id)
        else if (_.includes(channels, channel.name))
          channels.splice(channels.indexOf(channel.name), 1)
          res.push(channel.id)
        else if (_.includes(channels, channel.nice_name))
          channels.splice(channels.indexOf(channel.nice_name), 1)
          res.push(channel.id)
      return res

  # find user/s, return id array
  #
  # users: array of users or string: accepting nick, email, id
  #
  # returns array of user ids
  findUsersID: (users) ->
    res = []
    if (typeof users == 'string')
      users = [users]
    return @usersList()
    .then (userList) ->
      for user in userList
        if (_.includes(users, user.name))
          users.splice(users.indexOf(user.name), 1)
          res.push(user.id)
        else if (_.includes(users, user.email))
          users.splice(users.indexOf(user.email), 1)
          res.push(user.id)
        else if (_.includes(users, user.id))
          users.splice(users.indexOf(user.id), 1)
          res.push(user.id)
      return res


  # robot: robot object
  # msg: hubot message object
  # message: custom message object or str (for basic)
  #   text: text message
  #   color: hex color representation or 'green/yellow/red'
  #   title: message title
  #   link: url
  #   image: url
  #   footer: string
  #   footer_icon: url
  # opt: opt obj
  #   room: room name, id, DM id, username with @ prefix
  #   user: username
  # reply: true/false: prefix message with @#{opt.user}
  customMessage: (robot, msg, message, opt, reply) ->
    _this = @
    if (typeof message == 'string')
      toSend = message
    else
      toSend = []
      if message.title
        toSend.push(message.title)
      if message.text
        toSend.push(message.text)
      if message.link
        if message.link_desc
          toSend.push(message.link_desc+": "+message.link)
        else
          toSend.push(message.link)
      if message.footer
        toSend.push(message.footer)
      toSend = toSend.join('\n')
    if (reply && !opt.custom_msg)
      return msg.respond(toSend)
    # sending the message
    if (reply && (opt.user && opt.room[0] !='@'))
      userText = if (opt.user[0] != '@') then '@'+opt.user else opt.user
      toSend = userText+", "+toSend
    if opt.room[0] == '#'
      # resolve channel name to id
      new Promise (resolve, reject) ->
        return _this.findChannels(opt.room.replace('#', ''))
        .then (channels) ->
          resolve(robot.send {room: channels[0]}, toSend)
    if opt.room[0] == '@'
      # resolve room user name to id
      new Promise (resolve, reject) ->
        return _this.findUsersID(opt.room.replace('@', ''))
        .then (users) ->
          resolve(robot.send {user: {id: users[0]}}, toSend)

module.exports = Adapter
