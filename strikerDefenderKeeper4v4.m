function results = strikerDefenderKeeper4v4(n, firstSeed, animate)
%STRIKERDEFENDERKEEPER4V4  Two teams of four play a match on the full pitch.
%
%   strikerDefenderKeeper4v4             ask how many matches to play
%   strikerDefenderKeeper4v4(1)          watch one match
%   strikerDefenderKeeper4v4(50)         play 50 matches without drawing (fast)
%   strikerDefenderKeeper4v4(1, 7)       replay match 7 exactly (match k uses random seed k)
%   results = strikerDefenderKeeper4v4(20, 1, false)   no drawing, just return the results
%
%   Up to 3 matches are animated by default. When more than one match is
%   played, the results are saved in a 'results4v4' folder next to this file:
%   a summary table (CSV), an event log (TXT), every trajectory (MAT) and an
%   overview picture (PNG).
%
%   2D, seen from above, in metres and seconds. Full 9 m x 6 m pitch from the
%   ENG5325 spec with the origin on the centre spot. BLUE attacks the goal at
%   x = +4.5, RED attacks the goal at x = -4.5. Goals are 2.6 m wide.
%   Each team has a keeper (K), a defender (D) and two strikers (1, 2), and
%   both teams run the same code. Every team thinks in its own frame where it
%   attacks +x, so x from 0 to 4.5 is the same attacking half as in the
%   one-sided strikerDefenderKeeper.m.
%   Outcomes come from what physically happens to the ball: touching a robot
%   (checked along the ball's whole path in each step), crossing a goal line
%   or a touch line.
%
%   Strikers swap roles during play depending on who is nearer the ball:
%     we have the ball    HOLD     holder: shoot if in range with a clear shot
%                                  (or under pressure, or held too long), else
%                                  pass to the other striker once it is onside
%                         SUPPORT  other striker finds space (old shooter RUN)
%     our pass rolling    RECEIVE  receiver goes to the ball, other SUPPORT
%     ball loose          CHASE    nearer striker goes to the ball
%     they have the ball  PRESS    nearer striker runs at the holder; a touch
%                                  knocks the ball loose (tackle)
%                         COVER    other striker blocks the pass to their
%                                  free striker
%     their restart       WAIT     keep P.restartDist away until it is taken
%   Robots push each other apart when they overlap (the ball holder stands firm).
%   A striker needs P.kickPrep seconds after taking control before it can kick.
%   There is no dribbling: a striker with the ball stays where it is.
%   Defender  GUARD     stand between the ball and our goal (further out when
%                       the ball is far away)
%             ATTACK    ball is close and not ours: run at it. Any touch clears
%                       the ball upfield.
%   Keeper    slide along our goal line to where the ball will cross it, after
%             a short reaction delay. Any touch is a save and a clearance.
%   Ball out: kick-in, goal kick or corner for the other team.
%   After a goal: kick-off for the team that conceded.

if nargin < 1, n = 0; end
while ~(isscalar(n) && n >= 1 && n == round(n))
    n = input('How many matches? ');
end
if nargin < 2, firstSeed = 1; end
if nargin < 3, animate = (n <= 3); end

%% Settings
P.dt = 0.05;           P.matchTime = 600;     % s, one 10-minute half
P.halfL = 4.5;         P.halfW = 3;           % m, pitch is 9 m x 6 m
P.goalHalfW = 1.3;     P.goalDepth = 0.6;     % m
P.border = 1;                                 % m, border strip around the pitch
P.ballR = 0.07;        P.friction = 0.3;      % m, m/s^2
P.robotR = 0.15;                              % m, strikers and defenders
P.walkV = 0.25;        % m/s, strikers
P.controlSpeed = 1.0;  % m/s, a striker can only take control of a ball slower than this
P.shotSpeed = 2.0;     P.shotNoise = 0.08;    % m/s, rad
P.shootRange = 3.5;    % m, only shoot from this close to the goal
P.passNoise = 0.05;    P.passSpeedNoise = 0.1;% rad, fraction
P.laneClear = 0.8;     % m, pass if every opponent is this far from the pass line
P.shotClear = 0.5;     % m, shoot if every opponent is this far from the shot line
P.pressureDist = 0.6;  % m, opponent this close to the ball: pass or shoot now
P.maxHold = 4;         % s, pass or shoot anyway after holding the ball this long
P.kickPrep = 0.5;      % s, time to turn and set up a kick after taking control
P.aimInside = 0.4;     % m, aim at least this far inside the posts
P.supportMaxX = 3.0;   % m, the support striker waits at least 1.5 m from the goal line
P.supportAhead = 2.5;  % m, ...and at most this far ahead of the ball
P.onsideMargin = 0.15; % m, the support striker stays this far behind the offside line
P.chaseBias = 0.3;     % m, the other striker must be this much nearer to take over the chase
P.keeperX = 4.3;       P.keeperV = 0.3;       P.keeperR = 0.25;  % m, m/s, m
P.keeperDelay = 0.15;  % s, keeper reaction time after each kick
P.defenderV = 0.3;     P.attackDist = 1.0;    % m/s, m
P.guardDist = 1.8;     P.guardMax = 3.5;      % m, guard distance from our goal (min, max)
P.clearDist = [2.5 4.0]; P.clearNoise = 0.2;  % m, rad: defender and keeper clear the ball
                                              % 2.5 to 4 m towards our striker furthest ahead
                                              % (2.5 m so it leaves faster than controlSpeed)
P.tackleSpeed = 1.2;   % m/s, a striker's tackle knocks the ball this fast
P.touchGuard = 0.5;    % s, a robot can't touch the ball again this soon after kicking it
P.restartDist = 0.75;  % m, opponents keep this far away at kick-offs and restarts
P.restartWait = 10;    % s, ...for at most this long
% random kick-off areas in the team's own frame (own half is x < 0), [xmin xmax; ymin ymax]
P.kickerStart   = [-0.8 -0.4; -0.3 0.3];      % striker 1 of the team kicking off
P.strikerStart  = [-2.0 -1.0; -1.5 1.5];      % all other strikers
P.defenderStart = [-3.2 -2.5; -1.0 1.0];
P.drawEvery = 3;       % draw every 3rd step when animating

%% Play
results = [];
for k = 1:n
    r = playOne(P, firstSeed + k - 1, animate);
    results = [results; r]; %#ok<AGROW>
    if n <= 20
        fprintf('Match %3d:  BLUE %d - %d RED   shots %2d-%-2d  passes %2d-%-2d  tackles %2d-%-2d  possession %2.0f%%-%2.0f%%\n', ...
            r.Match, r.BlueGoals, r.RedGoals, r.BlueShots, r.RedShots, r.BluePasses, r.RedPasses, ...
            r.BlueTackles, r.RedTackles, r.BluePossession, 100 - r.BluePossession);
    end
    if animate && k < n, pause(1); end
end
w = {results.Winner};
fprintf('\nBLUE wins %d   draws %d   RED wins %d   (%.1f goals per match)\n', ...
    sum(strcmp(w, 'BLUE')), sum(strcmp(w, 'DRAW')), sum(strcmp(w, 'RED')), ...
    mean([results.BlueGoals] + [results.RedGoals]));
if n > 1
    folder = saveResults(results, P);
    showOverview(results, P, folder);
    fprintf('Results saved in %s\n', folder);
end
end


%% ------------------------------------------------------------------
function r = playOne(P, seed, animate)
rng(seed);                                   % same seed = same match
W.t = 0;  W.events = {};  W.score = [0 0];
W.shots = [0 0];  W.passes = [0 0];  W.tackles = [0 0];  W.saves = [0 0];  W.poss = [0 0];
W.shotLog = zeros(0, 4);                     % [x y team scored]
roles = {'K', 'D', 'S1', 'S2'};
for t = 1:2
    for j = 1:4
        W.bots((t - 1) * 4 + j) = struct('team', t, 'role', roles{j}(1), ...
            'name', [teamName(t) '-' roles{j}], 'pos', [0 0], 'mode', '', 'held', 0, 'logged', false);
    end
end
W = kickoff(W, P, 1);                        % BLUE kicks off

N = round(P.matchTime / P.dt) + 1;
track.ball = nan(N, 2);  track.bots = nan(N, 16);   % bot i: columns 2i-1 (x) and 2i (y)
if animate
    figure(1); clf; set(gcf, 'Color', [0.96 0.97 0.98], 'Position', [60 80 1350 620]);
end

for step = 1:N
    W.t = (step - 1) * P.dt;
    if W.restartTeam && W.t - W.restartTime > P.restartWait, W.restartTeam = 0; end
    old = W;
    order = [1 2];  if mod(step, 2) == 0, order = [2 1]; end   % take turns deciding first
    for t = order, W = teamStep(W, P, t); end  % 1. everyone decides and moves
    W = separate(W, P);                      %    robots can't stand inside each other
    W = rollBall(W, P);                      % 2. a free ball rolls and slows down
    [W, scorer] = resolve(W, old, P);        % 3. touches, goal lines, touch lines
    track.ball(step, :) = W.ball.pos;  track.bots(step, :) = [W.bots.pos];
    if W.ball.owner, t = W.bots(W.ball.owner).team;
    elseif W.lastTouch, t = W.bots(W.lastTouch).team; else, t = 0; end
    if t, W.poss(t) = W.poss(t) + P.dt; end
    if animate && (mod(step, P.drawEvery) == 1 || scorer)
        drawScene(W, P, seed);
    end
    if scorer
        if animate, pause(1); end
        W = kickoff(W, P, 3 - scorer);       % the team that conceded kicks off
    end
end
W = logEvent(W, 'FULL TIME: BLUE %d - %d RED', W.score(1), W.score(2));
if animate, drawScene(W, P, seed); end

winner = 'DRAW';
if W.score(1) > W.score(2), winner = 'BLUE'; elseif W.score(2) > W.score(1), winner = 'RED'; end
r = struct('Match', seed, 'BlueGoals', W.score(1), 'RedGoals', W.score(2), 'Winner', winner, ...
    'BlueShots', W.shots(1), 'RedShots', W.shots(2), 'BluePasses', W.passes(1), 'RedPasses', W.passes(2), ...
    'BlueTackles', W.tackles(1), 'RedTackles', W.tackles(2), 'BlueSaves', W.saves(1), 'RedSaves', W.saves(2), ...
    'BluePossession', 100 * W.poss(1) / max(sum(W.poss), eps), ...
    'Events', {W.events}, 'ShotLog', W.shotLog, 'ball', track.ball, 'bots', track.bots);
end


function W = kickoff(W, P, team)
% Everyone back to their own half; 'team' kicks off from the centre spot
for i = 1:8
    t = W.bots(i).team;
    switch W.bots(i).role
        case 'K', p = [-P.keeperX 0];
        case 'D', p = randomPoint(P.defenderStart);
        otherwise
            if t == team && W.bots(i).name(end) == '1', p = randomPoint(P.kickerStart);
            else, p = randomPoint(P.strikerStart); end
    end
    W.bots(i).pos = p * teamDir(t);
    W.bots(i).mode = '';  W.bots(i).held = 0;  W.bots(i).logged = false;
end
[W.bots([2 6]).mode] = deal('GUARD');
W.ball = struct('pos', [0 0], 'vel', [0 0], 'owner', 0);   % owner = index of the striker holding it
W.lastTouch = 0;  W.kicker = 0;  W.lastKick = -inf;  W.passTo = 0;  W.shotBy = 0;
W.chaser = [3 7];                            % which striker of each team goes for the ball
W.restartTeam = team;  W.restartTime = W.t;  % the other team keeps away until it's taken
W = logEvent(W, 'KICK-OFF for %s', teamName(team));
end


%% ------------------------------------------------------------------
function W = teamStep(W, P, t)
% Everyone in team t decides and moves. All thinking happens in the team's
% own frame (we attack +x); multiplying by d converts in both directions.
d   = teamDir(t);
ids = (t - 1) * 4 + (1:4);   S = ids(3:4);   % our keeper, defender, striker 1, striker 2
opp = (2 - t) * 4 + (1:4);                   % their keeper, defender, striker 1, striker 2
pos8 = reshape([W.bots.pos], 2, [])' * d;     % everyone's position, our frame
oppPos = pos8(opp, :);
ball = W.ball.pos * d;  bvel = W.ball.vel * d;
owner = W.ball.owner;  ownerTeam = 0;
if owner, ownerTeam = W.bots(owner).team; end
waiting = W.restartTeam ~= 0 && W.restartTeam ~= t;   % their kick-off or restart

% Who does what among the strikers
if ownerTeam == t
    modes = {'HOLD', 'SUPPORT'};      pair = [owner S(S ~= owner)];
elseif owner == 0 && any(W.passTo == S)
    modes = {'RECEIVE', 'SUPPORT'};   pair = [W.passTo S(S ~= W.passTo)];
else
    c = W.chaser(t);  o = S(S ~= c);
    if norm(pos8(o, :) - ball) < norm(pos8(c, :) - ball) - P.chaseBias, c = o; end
    W.chaser(t) = c;  pair = [c S(S ~= c)];
    if waiting, modes = {'WAIT', 'COVER'};
    elseif owner, modes = {'PRESS', 'COVER'};
    else, modes = {'CHASE', 'COVER'}; end
end

for j = 1:2
    i = pair(j);  s = W.bots(i);  s.mode = modes{j};  me = pos8(i, :);
    switch s.mode
        case 'HOLD'
            s.held = s.held + P.dt;
            mate = pos8(pair(2), :);
            R = mate + (P.robotR + P.ballR) * unit([P.halfL 0] - mate);   % mate's feet
            onside   = mate(1) <= offsideLine(ball, oppPos);
            laneOpen = minClearance(ball, R, oppPos) > P.laneClear;
            pressure = min(sqrt(sum((oppPos - ball).^2, 2))) < P.pressureDist;
            ready    = s.held >= P.kickPrep;
            inRange  = norm([P.halfL 0] - ball) < P.shootRange;
            [aim, clearance] = bestAim(ball, oppPos, P);
            if ready && inRange && (clearance > P.shotClear || pressure || s.held > P.maxHold)
                W = doKick(W, i, aim * d, P.shotSpeed, P.shotNoise, 0);
                W.shots(t) = W.shots(t) + 1;  W.shotBy = t;
                W.shotLog(end + 1, :) = [W.ball.pos t 0];
                W = logEvent(W, '%s shoots at y = %.2f m', s.name, aim(2) * d);
            elseif ready && onside && R(1) > ball(1) - 1 && (laneOpen || pressure || s.held > P.maxHold)
                speed = sqrt(2 * P.friction * norm(R - ball));   % so the ball stops at R
                W = doKick(W, i, R * d, speed, P.passNoise, P.passSpeedNoise);
                W.passes(t) = W.passes(t) + 1;  W.passTo = pair(2);
                W = logEvent(W, '%s passes to %s (%.2f m/s)', s.name, W.bots(pair(2)).name, norm(W.ball.vel));
            elseif ready && s.held > 2 * P.maxHold
                W = doKick(W, i, aim * d, P.shotSpeed, P.shotNoise, 0);
                W = logEvent(W, '%s kicks it long: nothing else on', s.name);
            elseif ready && ~s.logged
                W = logEvent(W, '%s holds the ball: no pass or shot on yet', s.name);  s.logged = true;
            end
        case 'SUPPORT'
            s.pos = walkTowards(me, findSpace(ball, oppPos, P), P.walkV, P.dt) * d;
        case {'RECEIVE', 'CHASE', 'PRESS'}
            s.pos = walkTowards(me, ball, P.walkV, P.dt) * d;
            if ~strcmp(s.mode, 'PRESS') && canControl(s, W.ball, P)
                [s, W] = takeControl(s, W, i);
            end
        case 'WAIT'
            target = ball + (P.restartDist + 0.1) * unit([-P.halfL 0] - ball);
            s.pos = walkTowards(me, target, P.walkV, P.dt) * d;
        case 'COVER'
            % stand on the pass line to their striker who doesn't have the ball
            theirS = opp(3:4);
            [~, k] = max(sqrt(sum((pos8(theirS, :) - ball).^2, 2)));
            target = ball + 0.6 * (pos8(theirS(k), :) - ball);
            if waiting && norm(target - ball) < P.restartDist + 0.1
                target = ball + (P.restartDist + 0.1) * unit(target - ball);
            end
            s.pos = walkTowards(me, target, P.walkV, P.dt) * d;
    end
    W.bots(i) = s;
end

% Defender
i = ids(2);  s = W.bots(i);  me = pos8(i, :);  dist = norm(ball - me);
mayAttack = ownerTeam ~= t && ~waiting;
if strcmp(s.mode, 'GUARD') && dist < P.attackDist && mayAttack
    s.mode = 'ATTACK';  W = logEvent(W, '%s attacks the ball', s.name);
elseif strcmp(s.mode, 'ATTACK') && (dist > P.attackDist + 0.5 || ~mayAttack)
    s.mode = 'GUARD';   W = logEvent(W, '%s drops back to guard', s.name);
end
if strcmp(s.mode, 'GUARD')
    goal   = [-P.halfL 0];
    reach  = min(max(P.guardDist, 0.4 * norm(ball - goal)), P.guardMax);
    target = goal + reach * unit(ball - goal);    % between the ball and our goal
else
    target = ball;
end
s.pos = walkTowards(me, target, P.defenderV, P.dt) * d;
W.bots(i) = s;

% Keeper: slide to where the ball will cross our line
i = ids(1);  y = 0;                          % no shot: wait in the middle
if bvel(1) < -0.1 && W.t >= W.lastKick + P.keeperDelay
    y = ball(2) + bvel(2) * (-P.keeperX - ball(1)) / bvel(1);
end
y = clamp(y, P.goalHalfW);
W.bots(i).pos = walkTowards(pos8(i, :), [-P.keeperX y], P.keeperV, P.dt) * d;
W.bots(i).mode = 'KEEP';
end


%% ------------------------------------------------------------------
function target = findSpace(ball, oppPos, P)
% Onside, not too close to goal, not too far ahead of the ball, and where
% the pass line is furthest from every opponent (small preference for
% central and nearby spots). Team frame.
x  = min([offsideLine(ball, oppPos) - P.onsideMargin, P.supportMaxX, ball(1) + P.supportAhead]);
ys = -2:0.5:2;
score = arrayfun(@(y) minClearance(ball, [x y], oppPos) - 0.2 * abs(y) ...
                      - 0.15 * norm([x y] - ball), ys);
[~, best] = max(score);
target = [x ys(best)];
end


function [aim, clearance] = bestAim(ball, oppPos, P)
% Try spots across their goal and pick the one whose shot line stays
% furthest from all four opponents. Team frame.
best = -inf;
for y = linspace(-1, 1, 9) * (P.goalHalfW - P.aimInside)
    target = [P.halfL y];
    score = minClearance(ball, target, oppPos);
    if score > best, best = score; aim = target; end
end
clearance = best;
end


function x = offsideLine(ball, oppPos)
% Offside = nearer their goal line than both the ball and the second-last
% opponent, and only in their half (x > 0). Team frame.
xs = sort(oppPos(:, 1), 'descend');
x = max([xs(2), ball(1), 0]);
end


function W = separate(W, P)
% Push overlapping robots apart. The striker holding the ball doesn't move,
% so the ball stays at its feet.
r = P.robotR * ones(1, 8);  r([W.bots.role] == 'K') = P.keeperR;
for i = 1:7
    for j = i + 1:8
        d = W.bots(j).pos - W.bots(i).pos;  gap = norm(d) - r(i) - r(j);
        if gap >= 0, continue; end
        u = unit(d);  share = [0.5 0.5];
        if W.ball.owner == i, share = [0 1]; elseif W.ball.owner == j, share = [1 0]; end
        W.bots(i).pos = W.bots(i).pos + share(1) * gap * u;
        W.bots(j).pos = W.bots(j).pos - share(2) * gap * u;
    end
end
end


function W = rollBall(W, P)
if W.ball.owner, return; end                 % a held ball stays at the striker's feet
speed = norm(W.ball.vel);
if speed > 0, W.ball.vel = W.ball.vel * max(speed - P.friction * P.dt, 0) / speed; end
W.ball.pos = W.ball.pos + W.ball.vel * P.dt;
end


%% ------------------------------------------------------------------
function [W, scorer] = resolve(W, old, P)
% Work out what the ball touched first during this step, then what happens
scorer = 0;
b0 = old.ball.pos;  b1 = W.ball.pos;
owner = W.ball.owner;  ownerTeam = 0;
if owner, ownerTeam = W.bots(owner).team; end
hit = inf(1, 9);                             % fraction of the step (0 to 1), inf = no touch
for i = 1:8
    s = W.bots(i);
    if s.team == ownerTeam, continue; end                    % nobody tackles a teammate
    if i == W.kicker && W.t - W.lastKick < P.touchGuard, continue; end      % just kicked it
    if s.role == 'S' && owner == 0, continue; end            % strikers take a loose ball by controlling it
    R = P.robotR;  if s.role == 'K', R = P.keeperR; end
    hit(i) = contactTime(b0 - old.bots(i).pos, b1 - s.pos, R + P.ballR);
end
lineX = P.halfL + P.ballR;                   % ball centre here = whole ball over the line
if abs(b0(1)) < lineX && abs(b1(1)) >= lineX
    hit(9) = (lineX - abs(b0(1))) / (abs(b1(1)) - abs(b0(1)));
end
first = min(hit);  tied = find(hit == first);
who = tied(randi(numel(tied)));              % same instant: pick one at random, not always BLUE
if isfinite(first), W.ball.pos = b0 + first * (b1 - b0); end   % back to where it happened
pos = W.ball.pos;

if ~isfinite(first)
    if abs(pos(2)) > P.halfW + P.ballR       % over a touch line: kick-in
        W = restart(W, P, [clamp(pos(1), P.halfL - 0.3), sign(pos(2)) * (P.halfW - 0.2)], ...
            'kick-in', otherTeam(W));
    end
elseif who == 9                              % over a goal line
    side = sign(pos(1));  defending = 1.5 + side / 2;   % RED defends +x, BLUE defends -x
    if abs(pos(2)) < P.goalHalfW
        scorer = 3 - defending;
        W.score(scorer) = W.score(scorer) + 1;
        if W.shotBy == scorer && ~isempty(W.shotLog), W.shotLog(end, 4) = 1; end
        W.ball.vel = [0 0];
        W = logEvent(W, 'GOAL for %s! (%d - %d)', teamName(scorer), W.score(1), W.score(2));
    elseif otherTeam(W) == defending         % attackers put it out: goal kick
        W = restart(W, P, [side * (P.halfL - 1), sign(pos(2)) * 1.5], 'goal kick', defending);
    else                                     % defenders put it out: corner
        W = restart(W, P, [side * (P.halfL - 0.2), sign(pos(2)) * (P.halfW - 0.2)], ...
            'corner', 3 - defending);
    end
else                                         % a robot touched it
    s = W.bots(who);  t = s.team;  d = teamDir(t);
    if owner
        what = ['tackles ' W.bots(owner).name];  W.tackles(t) = W.tackles(t) + 1;
    elseif W.shotBy == 3 - t && s.role == 'K'
        what = 'saves';  W.saves(t) = W.saves(t) + 1;
    elseif W.shotBy == 3 - t
        what = 'blocks the shot';
    elseif W.passTo && W.bots(W.passTo).team ~= t
        what = 'intercepts the pass';
    else
        what = 'gets to the ball';
    end
    here = pos * d;                          % every touch sends the ball upfield (team frame)
    if s.role == 'S'                         % a striker's tackle just knocks it loose
        target = here + [1 0];  speed = P.tackleSpeed;  noise = 0.5;
    else                                     % keeper/defender: towards our striker furthest ahead
        mates = reshape([W.bots((t - 1) * 4 + (3:4)).pos], 2, [])' * d;
        [mx, k] = max(mates(:, 1));
        if mx > here(1) + 0.5, aim = mates(k, :); else, aim = here + [P.clearDist(2) 0]; end
        dist   = min(max(norm(aim - here), P.clearDist(1)), P.clearDist(2));
        target = here + dist * unit(aim - here);
        speed  = sqrt(2 * P.friction * dist);   % so the ball stops about there
        noise  = P.clearNoise;
    end
    W.ball.owner = 0;
    W = doKick(W, who, target * d, speed, noise, 0);
    W = logEvent(W, '%s %s and clears', s.name, what);
end
end


function W = restart(W, P, spot, what, team)
% Ball out: put it back at 'spot'; the other side keeps away until 'team' takes it
W.ball = struct('pos', spot, 'vel', [0 0], 'owner', 0);
W.lastTouch = 0;  W.kicker = 0;  W.lastKick = W.t;  W.passTo = 0;  W.shotBy = 0;
W.restartTeam = team;  W.restartTime = W.t;
W = logEvent(W, 'Ball out: %s for %s', what, teamName(team));
end


%% Small helpers
function ok = canControl(s, b, P)
ok = b.owner == 0 && norm(s.pos - b.pos) <= P.robotR + P.ballR + 0.02 ...
     && norm(b.vel) <= P.controlSpeed;
end

function [s, W] = takeControl(s, W, i)
W.ball.owner = i;  W.ball.vel = [0 0];
W.lastTouch = i;  W.passTo = 0;  W.shotBy = 0;
s.mode = 'HOLD';  s.held = 0;  s.logged = false;
W = logEvent(W, '%s takes control of the ball', s.name);
end

function W = doKick(W, i, target, speed, angleNoise, speedNoise)
b = W.ball;  dd = target - b.pos;
a = atan2(dd(2), dd(1)) + angleNoise * randn;
W.ball.vel = speed * (1 + speedNoise * randn) * [cos(a) sin(a)];
W.ball.owner = 0;
W.lastTouch = i;  W.kicker = i;  W.lastKick = W.t;  W.passTo = 0;  W.shotBy = 0;  W.restartTeam = 0;
end

function t = otherTeam(W)
% The team that didn't touch the ball last
t = 1;
if W.lastTouch, t = 3 - W.bots(W.lastTouch).team; end
end

function c = minClearance(from, to, pts)
% Smallest distance from any of the points to the line from -> to
c = inf;
for k = 1:size(pts, 1), c = min(c, laneClearance(from, to, pts(k, :))); end
end

function c = laneClearance(from, to, p)
% Shortest distance from point p to the line from -> to
d = to - from;
s = max(0, min(1, dot(p - from, d) / dot(d, d)));
c = norm(p - (from + s * d));
end

function alpha = contactTime(a, b, radius)
% The ball moves from a to b relative to a robot during one step. Returns
% the fraction of the step (0 to 1) when it first touches, or inf.
alpha = inf;
if dot(a, a) <= radius^2, alpha = 0; return; end
v = b - a;  A = dot(v, v);  B = 2 * dot(a, v);  C = dot(a, a) - radius^2;
disc = B^2 - 4 * A * C;
if A < 1e-12 || disc < 0, return; end
root = (-B - sqrt(disc)) / (2 * A);
if root >= 0 && root <= 1, alpha = root; end
end

function W = logEvent(W, fmt, varargin)
W.events{end + 1} = sprintf(['%6.2fs  ' fmt], W.t, varargin{:});
end

function p = walkTowards(p, target, v, dt)
% Straight line, at most speed v, never overshooting
d = target - p;
if norm(d) > 0, p = p + min(norm(d), v * dt) * unit(d); end
end

function p = randomPoint(box)
p = box(:, 1)' + rand(1, 2) .* (box(:, 2) - box(:, 1))';
end

function y = clamp(y, limit)
y = max(min(y, limit), -limit);
end

function u = unit(v)
if norm(v) < 1e-10, u = [1 0]; else, u = v / norm(v); end
end

function d = teamDir(t)
d = 3 - 2 * t;                               % BLUE +1, RED -1
end

function s = teamName(t)
names = {'BLUE', 'RED'};  s = names{t};
end


%% ------------------------------------------------------------------
function folder = saveResults(results, P)
folder = fullfile(fileparts(mfilename('fullpath')), 'results4v4');
if ~exist(folder, 'dir'), mkdir(folder); end
fid = fopen(fullfile(folder, 'summary.csv'), 'w');
fprintf(fid, ['Match,BlueGoals,RedGoals,Winner,BlueShots,RedShots,BluePasses,RedPasses,' ...
              'BlueTackles,RedTackles,BlueSaves,RedSaves,BluePossession\n']);
for r = results'
    fprintf(fid, '%d,%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%.1f\n', r.Match, r.BlueGoals, r.RedGoals, ...
        r.Winner, r.BlueShots, r.RedShots, r.BluePasses, r.RedPasses, r.BlueTackles, r.RedTackles, ...
        r.BlueSaves, r.RedSaves, r.BluePossession);
end
fclose(fid);
fid = fopen(fullfile(folder, 'events.txt'), 'w');
for r = results'
    fprintf(fid, 'Match %d: BLUE %d - %d RED\n', r.Match, r.BlueGoals, r.RedGoals);
    fprintf(fid, '  %s\n', r.Events{:});
    fprintf(fid, '\n');
end
fclose(fid);
save(fullfile(folder, 'results.mat'), 'results', 'P', '-v7');
end


function showOverview(results, P, folder)
% Shot map of every match, goals per match, and team averages
fig = figure(2); clf; set(fig, 'Color', 'w', 'Position', [60 60 1400 640]);
colours = [0.15 0.45 1; 0.9 0.2 0.2];

subplot(1, 2, 1);  drawPitch(P);
shots = vertcat(results.ShotLog);
for t = 1:2
    m = shots(:, 3) == t;
    plot(shots(m & ~shots(:, 4), 1), shots(m & ~shots(:, 4), 2), 'o', 'Color', colours(t, :), 'MarkerSize', 5);
    plot(shots(m & shots(:, 4) == 1, 1), shots(m & shots(:, 4) == 1, 2), 'o', ...
        'MarkerFaceColor', colours(t, :), 'MarkerEdgeColor', 'w', 'MarkerSize', 7);
end
title('Where shots were taken from (filled = goal)   BLUE attacks right, RED attacks left', 'FontSize', 10);
hold off;

subplot(2, 2, 2);
h = bar([results.Match], [[results.BlueGoals]' [results.RedGoals]'], 'grouped');
set(h(1), 'FaceColor', colours(1, :));  set(h(2), 'FaceColor', colours(2, :));
xlabel('Match');  ylabel('Goals');  title('Goals per match', 'FontSize', 10);  legend('BLUE', 'RED');

subplot(2, 2, 4);
avg = @(f) mean([results.(f)]);
vals = [avg('BlueShots') avg('RedShots'); avg('BluePasses') avg('RedPasses'); ...
        avg('BlueTackles') avg('RedTackles'); avg('BlueSaves') avg('RedSaves'); ...
        avg('BluePossession') / 10, (100 - avg('BluePossession')) / 10];
h = bar(vals, 'grouped');
set(h(1), 'FaceColor', colours(1, :));  set(h(2), 'FaceColor', colours(2, :));
set(gca, 'XTick', 1:5, 'XTickLabel', {'Shots', 'Passes', 'Tackles', 'Saves', 'Possession/10 (%)'});
title('Average per match', 'FontSize', 10);

w = {results.Winner};
annotation(fig, 'textbox', [0 0.94 1 0.06], 'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 13, 'FontWeight', 'bold', 'String', sprintf( ...
    '%d matches of %d s: BLUE wins %d | draws %d | RED wins %d   (%.1f goals per match)', ...
    numel(w), P.matchTime, sum(strcmp(w, 'BLUE')), sum(strcmp(w, 'DRAW')), sum(strcmp(w, 'RED')), ...
    mean([results.BlueGoals] + [results.RedGoals])));
print(fig, fullfile(folder, 'overview.png'), '-dpng', '-r150');
end


%% ------------------------------------------------------------------
function drawPitch(P)
cla; hold on; axis equal;
L = P.halfL;  H = P.halfW;  B = P.border;
axis([-L - B, L + B, -H - B, H + B]);
set(gca, 'XTick', [], 'YTick', []);
fill([-L - B, L + B, L + B, -L - B], [-H - B, -H - B, H + B, H + B], [0.10 0.34 0.24], 'EdgeColor', 'none');
box = @(x0, x1, hw) plot([x0 x1 x1 x0 x0], hw * [-1 -1 1 1 -1], 'w', 'LineWidth', 1.2);
box(-L, L, H);                                                     % touch and goal lines
plot([0 0], [-H H], 'w', 'LineWidth', 1.2);                         % halfway line
a = linspace(0, 2 * pi, 80);
plot(0.75 * cos(a), 0.75 * sin(a), 'w', 'LineWidth', 1.2);          % centre circle
for s = [-1 1]
    box(s * L, s * (L - 1), 1.5);                                   % goal area 1 m x 3 m
    box(s * L, s * (L - 2), 2.5);                                   % penalty area 2 m x 5 m
    plot(s * (L - 1.5), 0, 'w+');                                   % penalty mark
    plot(s * (L + [0 P.goalDepth P.goalDepth 0]), P.goalHalfW * [-1 -1 1 1], 'w', 'LineWidth', 2.5);  % goal
end
plot(0, 0, 'w+');
end


function drawScene(W, P, seed)
drawPitch(P);
set(gca, 'Position', [0.02 0.08 0.66 0.84]);
cols = {[0.15 0.45 1], [0.9 0.2 0.2]};
for i = 1:8
    s = W.bots(i);  r = P.robotR;
    if s.role == 'K', r = P.keeperR; end
    disc(s.pos, r, cols{s.team});
    label = s.role;  if label == 'S', label = s.name(end); end
    text(s.pos(1), s.pos(2), label, 'Color', 'w', 'FontSize', 8, 'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
end
disc(W.ball.pos, P.ballR, [1 0.65 0]);
title(sprintf('Match %d   t = %5.1f s      BLUE %d - %d RED      (BLUE attacks right)', ...
    seed, W.t, W.score(1), W.score(2)), 'FontSize', 13);
lines = {};
for i = 1:8, lines{end + 1, 1} = sprintf('%-8s %s', W.bots(i).name, W.bots(i).mode); end %#ok<AGROW>
lines = [lines; {''; 'EVENTS'}; W.events(max(1, end - 11):end)'];
text(1.02, 1, lines, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
     'FontName', 'FixedWidth', 'FontSize', 9, 'Interpreter', 'none');
hold off; drawnow; pause(0.02);
end

function disc(p, r, colour)
a = linspace(0, 2 * pi, 40);
fill(p(1) + r * cos(a), p(2) + r * sin(a), colour, 'EdgeColor', 'w');
end
