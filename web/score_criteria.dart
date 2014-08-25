part of repo_scorecard;

class ScoreCriteria {
  @observable String name;
  @observable dynamic internval;
  @observable int score;
  @observable int maxScore;
  @observable dynamic prettyValue;
  Function visibleValue;

  get value => internval;

  set value(val) {
    internval = val;
    prettyValue = visibleValue != null ? visibleValue(val) : val;
  }

  // Note: Cannot use simple value constructor because of value setter
  ScoreCriteria(name, value, score, maxScore, {Function visibleValue}) {
    this.name = name;
    this.value = value;
    this.score = score;
    this.maxScore = maxScore;
    this.visibleValue = visibleValue;
  }

  ScoreCriteria.fromSteps(String name, dynamic value, List scoreSteps, int maxScore, {Function visibleValue}) :
    this(name, value, _getScore(value, scoreSteps), maxScore, visibleValue: visibleValue);

  calculateScore(List steps) {
    score = _getScore(value, steps);
  }

  static int _getScore(dynamic value, List steps) {
    int score = 0;
    while(score < steps.length && value >= steps[score] ) {
      score++;
    }
    return score;
  }

  String get scoreClass {
    if(maxScore == 0)
      return '';

    num percent = score / maxScore;
    var scoreClasses = ['Fail', 'Bad', 'Decent', 'Good', 'Excellent'];
    return scoreClasses[max((percent * (scoreClasses.length)).round()-1, 0)];
  }

}