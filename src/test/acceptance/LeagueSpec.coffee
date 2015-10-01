should = require 'should'
_ = require 'lodash'
Freesheet = require '../freesheet/Freesheet'

describe 'League Table calculation', ->

  class SheetOutputs
    constructor: (@sheet, @outputNames...) ->
      @values = {}
      for n in @outputNames
        callback = (name, value) => @values[name] = value
        @sheet.onValueChange callback, n

      @all = {}
      @sheet.onValueChange (name, value) => @all[name] = value

  it 'has sorted team positions after two inputs', ->
    freesheet = new Freesheet()
    sheet = freesheet.createSheet('league')
    outputs = new SheetOutputs sheet, ['leagueTable']
    sheet.load code


#    sheet.input 'singleResult', {homeTeam: 'Leeds', homeGoals: 2, awayTeam: 'Hull', awayGoals: 3}
#    sheet.input 'singleResult', {homeTeam: 'Hull', homeGoals: 3, awayTeam: 'Liverpool', awayGoals: 0}

    console.log 'all', outputs.all
#    outputs.values.leagueTable.should.eql [{team: 'Hull', points: 6}
#      {team: 'Leeds', points: 0}
#      {team: 'Liverpool', points: 0}
#    ]


  code = '''
      allResults = ["Hull", "Leeds", "Hull"];
      resultPoints(result) = ifElse("Hull" == result, 3, 1);
      teamResults(team) = select(allResults, team == in);
      totalPoints(t) = sum(fromEach(teamResults(t), resultPoints(in)));
      teamPoints(t) = {team: t, points: totalPoints(t)};

      teamPointsHull = teamPoints("Hull");
      teamPointsLeeds = teamPoints("Leeds");
      teamPointsHullLeeds = fromEach(["Hull", "Leeds"], teamPoints(in) );



      '''

  originalCode = '''
      resultPoints(t, result) = {team: t,
        points: pointsFromMatch(team, result) };
      pointsFromMatch(team, result) = ifElse(winner(team, result), 3, ifElse(draw(result), 1, 0));
      winner(team, result) = team == result.homeTeam and result.homeGoals > result.awayGoals
          or team == result.awayTeam and result.awayGoals > result.homeGoals;
      draw(result) = result.homeGoals == result.awayGoals;
      teamResults(team) = select(allResults, isInvolved(in, team));
      isInvolved(result, team) = team == result.homeTeam or team == result.awayTeam;
      totalPoints(t) = sum(fromEach(teamResults(t), resultPoints(t, in).points));
      teamPoints(t) = {team: t, points: totalPoints(t)};

      singleResult = input;
      allResults = all(singleResult);
      awayTeams = fromEach(allResults, in.awayTeam);
      homeTeams = fromEach(allResults, in.homeTeam);
      teams = differentValues(homeTeams + awayTeams);
      competitionResults = fromEach(teams, teamPoints(in));
      leagueTable = sortBy(competitionResults, 0-in.points);

'''