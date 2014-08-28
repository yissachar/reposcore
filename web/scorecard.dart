library repo_scorecard;

import 'dart:async';
import 'dart:html';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:polymer/polymer.dart';
import 'package:github/browser.dart';
import 'package:github/common.dart';

part 'score_criteria.dart';

@CustomTag('score-card')
class Scorecard extends PolymerElement {
  GitHub github;
  final String githubUrl = 'https://api.github.com';
  @observable bool searchedForRepo;
  @observable bool repoFound;
  @observable bool rateLimitHit;
  @observable String rateLimitReset;
  @observable String repo;
  @observable String repoName;
  @observable String user;
  @observable String userAvatar;
  @observable String description;
  @observable ScoreCriteria totalCriteria = new ScoreCriteria('Total', 0, 0, 0);
  @observable List<ScoreCriteria> criterion = toObservable([]);

  Scorecard.created() : super.created() {
    initGitHub();
    github = new GitHub();
  }

  void handleKeyUp(KeyboardEvent event) {
    if(event.keyCode == KeyCode.ENTER) {
      processRepo();
    }
  }

  void processRepo() {

    var urlRegex = new RegExp(r'(https?:\/\/github\.com\/)?([^\/]+\/[^\/]+)');
    var repoMatch = urlRegex.firstMatch(repo);
    if(repoMatch == null) {
      searchedForRepo = true;
      repoFound = false;
      return;
    }

    var shortRepo = repoMatch.group(2);
    var repoVars = shortRepo.split('/');
    var repoSlug = new RepositorySlug(repoVars[0], repoVars[1]);

    criterion.clear();

    // Rank forks, stargazers, watchers, and wiki
    callApi(github.repository(repoSlug).then((Repository repo) {
      repoFound = true;
      user = repo.owner.login;
      userAvatar = repo.owner.avatarUrl;
      repoName = repo.name;

      criterion.add(new ScoreCriteria.fromSteps('Stargazers', repo.stargazersCount, [1, 10, 50, 100, 150], 5));
      criterion.add(new ScoreCriteria.fromSteps('Forks', repo.forksCount, [1, 10, 25, 50, 100], 5));
      int daysSinceUpdate =  new DateTime.now().difference(repo.pushedAt).inDays;
      int lastUpdateScore = daysSinceUpdate < 7  ? 3 :
                            daysSinceUpdate < 30 ? 2 :
                            daysSinceUpdate < 60 ? 1 : 0;
      criterion.add(new ScoreCriteria('Last Updated', new DateFormat('MMM d, yyyy').format(repo.pushedAt), lastUpdateScore, 3));
      description = repo.description;
    })
    .catchError((e) => repoFound = false, test: (e) => e is NotFound)
    .whenComplete(() => searchedForRepo = true));

    // Rank README file
    callApi(github.readme(repoSlug).then((file) {
      var scoreMap = {1: 'Tiny', 500: 'Short', 1800: 'Long'};
      var keys = scoreMap.keys.toList();
      int score = getScore(file.size, keys);
      criterion.add(new ScoreCriteria('Readme', scoreMap[keys[score-1]], score, 3));
    })
    .catchError((e) {
      criterion.add(new ScoreCriteria('Readme', 'None', 0, 3));
    }, test: (e) => e is NotFound));

    var openPR = getCount('$githubUrl/repos/$shortRepo/pulls?state=open&per_page=1');
    var closedPR = getCount('$githubUrl/repos/$shortRepo/pulls?state=closed&per_page=1');

    callApi(Future.wait([openPR, closedPR]).then((values) {
      int open = values[0];
      int closed = values[1];

      int ratioScore = closed > 0 ? getScore(open / closed, [0.05, 0.01], descending: true) : 0;
      int issueScore = getScore(open + closed, [1, 5, 10, 40, 90, 150]);
      int totalScore = ratioScore > 0 ? issueScore + ((issueScore / 4) * ratioScore).round() : issueScore;

      criterion.add(new ScoreCriteria('Pull Requests', '$open open, $closed closed', totalScore, 8));
    }));

    callApi(getCount('$githubUrl/repos/$shortRepo/contributors?per_page=1').then((count) {
      criterion.add(new ScoreCriteria.fromSteps('Contributors', count, [2, 3, 8, 15, 40], 5));
    }));

    var openIssues = getCount('$githubUrl/repos/$shortRepo/issues?state=open&per_page=1');
    var closedIssues = getCount('$githubUrl/repos/$shortRepo/issues?state=closed&per_page=1');

    callApi(Future.wait([openIssues, closedIssues]).then((values) {
      int open = values[0];
      int closed = values[1];

      int ratioScore = closed > 0 ? getScore(open / closed, [0.3, 0.15], descending: true) : 0;
      int issueScore = getScore(open + closed, [1, 5, 15, 50]);
      int totalScore = ratioScore > 0 ? issueScore + ((issueScore / 4) * ratioScore).round() : issueScore;

      criterion.add(new ScoreCriteria('Issues', '$open open, $closed closed', totalScore, 6));
    }));
  }

  int getScore(num value, List steps, {bool descending: false}) {
    int score = 0;

    if(descending) {
      while(score < steps.length && value <= steps[score]) {
        score++;
      }
    } else {
      while(score < steps.length && value >= steps[score]) {
        score++;
      }
    }

    return score;
  }

  callApi(Future api) {
    rateLimitHit = false;

    api.catchError((e) {
        searchedForRepo = false;
        github.rateLimit().then((rateLimit) {
          rateLimitReset = new DateFormat('MMM d, yyyy hh:mm a').format(rateLimit.resets);
          rateLimitHit = rateLimit.remaining == 0;
          searchedForRepo = true;
        });
    })
    .whenComplete(() {
      // Update score
      int score = 0;
      int maxScore = 0;
      criterion.forEach((e) => score += e.score);
      criterion.forEach((e) => maxScore += e.maxScore);
      totalCriteria = new ScoreCriteria('Total', 0, score, maxScore);
    });
  }

  Future<int> getCount(String api) {
    var completer = new Completer();

    var req = new HttpRequest();
    github.request("GET", api).then((response) {
      int count = 0;

      var linkHeader = response.headers['link'];

      if(linkHeader != null) {
        var regex = new RegExp(r'page=(\d+)>; rel="last"');
        var match = regex.firstMatch(linkHeader);

        if(match != null) {
          count = int.parse(match.group(1));
        }
      }

      completer.complete(count);
    });

    return completer.future;
  }
}

