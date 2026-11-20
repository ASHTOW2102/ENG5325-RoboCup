function results = strikerDefenderKeeper(n, firstSeed, animate)
%STRIKERDEFENDERKEEPER  Two strikers attack against a defender and a goalkeeper.
%
%   strikerDefenderKeeper              ask how many attacks to play
%   strikerDefenderKeeper(10)          watch 10 attacks, then show an overview
%   strikerDefenderKeeper(300)         play 300 attacks without drawing (fast)
%   strikerDefenderKeeper(1, 7)        replay attack 7 exactly (attack k uses random seed k)
%   results = strikerDefenderKeeper(50, 1, false)   no drawing, just return the results
%
%   Up to 10 attacks are animated by default. When more than one attack is
%   played, the results are saved in a 'results' folder next to this file:
%   a summary table (CSV), an event log (TXT), every trajectory (MAT) and an
%   overview picture of up to 10 attacks with different outcomes (PNG).
%
%   2D, seen from above, in metres and seconds. x runs along the pitch,
%   the goal line is at x = 4.5 and the goal is 2.6 m wide.
%   Outcomes come from what physically happens to the ball: touching a robot
%   (checked along the ball's whole path in each step, so a fast ball can't
%   slip through a robot), crossing the goal line, leaving the pitch, or stopping.
%
%   Passer    CHASE     walk to the ball and take control of it
%             DRIBBLE   carry the ball forward, away from the defender, and
%                       pass once the shooter is onside and either the lane is
%                       clear, the defender is closing in, or we held it too long
%   Shooter   RUN       find space: level with the defender (onside), not too
%                       close to goal, where the pass line is far from the defender
%             RECEIVE   the pass is on its way: go to the ball and take control
%             DRIBBLE   carry the ball sideways, away from the defender, and shoot
%                       once there is a clear shot (or under pressure, or too long)
%   A striker needs P.kickPrep seconds after taking control before it can kick.
%   Defender  GUARD     stand between the ball and the goal
%             ATTACK    ball is close: run at it. Any touch clears the ball.
%   Keeper    slide along the goal line to where the ball will cross it, after
%             a short reaction delay. Any touch is a save.

if nargin < 1, n = 0; end
while ~(isscalar(n) && n >= 1 && n == round(n))
    n = input('How many attacks? ');
end
if nargin < 2, firstSeed = 1; end
if nargin < 3, animate = (n <= 10); end

%% Settings
P.dt = 0.05;           P.maxTime = 25;        % s
P.goalX = 4.5;         P.goalHalfW = 1.3;     % m
P.ballR = 0.07;        P.friction = 0.3;      % m, m/s^2
P.robotR = 0.15;                              % m, strikers and defender
P.walkV = 0.25;        P.dribbleV = 0.18;     % m/s, strikers
P.controlSpeed = 1.0;  % m/s, a striker can only take control of a ball slower than this
P.carryGap = 0.23;     % m, how far in front of a dribbling striker the ball is
P.shotSpeed = 2.0;     P.shotNoise = 0.08;    % m/s, rad
P.passNoise = 0.05;    P.passSpeedNoise = 0.1;% rad, fraction
P.laneClear = 0.8;     % m, pass if the defender is this far from the pass line
P.shotClear = 0.5;     % m, shoot if the defender and keeper are this far from the shot line
P.pressureDist = 0.6;  % m, defender this close to the ball: pass or shoot now
P.maxHold = 4;         % s, pass or shoot anyway after holding the ball this long
P.kickPrep = 0.5;      % s, time to turn and set up a kick after taking control
P.aimInside = 0.4;     % m, aim at least this far inside the posts
P.shooterMaxX = 3.0;   % m, the shooter waits at least 1.5 m from the goal line
P.dribbleMaxX = 3.5;   % m, nobody dribbles closer to the goal than this
P.onsideMargin = 0.15; % m, the shooter stays this far behind the offside line
P.keeperX = 4.3;       P.keeperV = 0.3;       P.keeperR = 0.25;  % m, m/s, m
P.keeperDelay = 0.15;  % s, keeper reaction time after each kick
P.defenderV = 0.3;     P.guardDist = 1.8;     P.attackDist = 1.0; % m/s, m, m
P.clearSpeed = 2.5;    P.clearSafeX = 1.5;    % m/s, m
% random start areas, [xmin xmax; ymin ymax]
P.passerStart   = [0.5 1.5; -1.5 1.5];
P.shooterStart  = [1.5 2.5; -1.5 1.5];
P.defenderStart = [2.5 3.2; -1.0 1.0];
P.drawEvery = 2;       % draw every 2nd step when animating

%% Play
results = [];
for k = 1:n
    r = playOne(P, firstSeed + k - 1, animate);
    results = [results; r]; %#ok<AGROW>
    if n <= 20
        fprintf('Attack %3d: %-8s %5.1f s  passes %d  shots %d  defender touches %d  dribbling %.1f s\n', ...
            r.Attack, r.Outcome, r.Seconds, r.Passes, r.Shots, r.DefenderTouches, r.DribbleSeconds);
    end
    if animate && k < n, pause(1); end
end
fprintf('\n');
for name = {'GOAL', 'SAVE', 'CLEARED', 'MISS', 'TIMEOUT'}
    hits = strcmp({results.Outcome}, name{1});
    fprintf('%-8s %5d  (%3.0f%%)\n', name{1}, sum(hits), 100 * mean(hits));
end
if n > 1
    folder = saveResults(results, P);
    showOverview(results, P, folder);
    fprintf('Results saved in %s\n', folder);
end
end


%% ------------------------------------------------------------------
function r = playOne(P, seed, animate)
rng(seed);                                   % same seed = same attack
W.t = 0;  W.events = {};  W.lastKick = -inf;  W.lastTouch = 'NONE';
W.passes = 0;  W.shots = 0;  W.touches = 0;  W.dribbleTime = 0;
W.defender = struct('pos', randomPoint(P.defenderStart), 'state', 'GUARD');
W.shooter  = struct('pos', randomPoint(P.shooterStart), 'state', 'RUN', 'held', 0, 'side', 1, 'logged', false);
W.shooter.pos(1) = min(W.shooter.pos(1), W.defender.pos(1) - P.onsideMargin);  % start onside
W.passer   = struct('pos', randomPoint(P.passerStart), 'state', 'CHASE', 'held', 0, 'side', 1, 'logged', false);
W.ball     = struct('pos', W.passer.pos + 0.4 * unit(W.shooter.pos - W.passer.pos), ...
                    'vel', [0 0], 'owner', '');
W.keeper   = [P.keeperX 0];

N = round(P.maxTime / P.dt) + 1;
names = {'ball', 'passer', 'shooter', 'defender', 'keeper'};
for j = 1:numel(names), track.(names{j}) = nan(N, 2); end
if animate
    figure(1); clf; set(gcf, 'Color', [0.96 0.97 0.98], 'Position', [100 100 1100 600]);
end

outcome = '';
for step = 1:N
    W.t = (step - 1) * P.dt;
    old = W;
    W = passerStep(W, P);                    % 1. everyone decides and moves
    W = shooterStep(W, P);
    W = defenderStep(W, P);
    W = keeperStep(W, P);
    W = rollBall(W, P);                      % 2. a free ball rolls and slows down
    [W, outcome] = resolve(W, old, P);       % 3. touches, goal line, pitch edge
    track.ball(step, :) = W.ball.pos;    track.passer(step, :) = W.passer.pos;
    track.shooter(step, :) = W.shooter.pos;  track.defender(step, :) = W.defender.pos;
    track.keeper(step, :) = W.keeper;
    if animate && (mod(step, P.drawEvery) == 1 || ~isempty(outcome))
        drawScene(W, track, step, seed, outcome, P);
    end
    if ~isempty(outcome), break; end
end
if isempty(outcome)
    outcome = 'TIMEOUT';
    W = logEvent(W, 'TIMEOUT: neither side finished the attack');
    if animate, drawScene(W, track, step, seed, outcome, P); end
end

r = struct('Attack', seed, 'Outcome', outcome, 'Seconds', W.t, 'Passes', W.passes, ...
    'Shots', W.shots, 'DefenderTouches', W.touches, 'DribbleSeconds', W.dribbleTime, ...
    'Events', {W.events});
for j = 1:numel(names), r.(names{j}) = track.(names{j})(1:step, :); end
end


%% ------------------------------------------------------------------
function W = passerStep(W, P)
s = W.passer;  b = W.ball;
switch s.state
    case 'CHASE'
        s.pos = walkTowards(s.pos, b.pos, P.walkV, P.dt);
        if canControl(s, b, P)
            [s, b] = takeControl(s, b, 'passer', W.defender);
            W = logEvent(W, 'PASSER takes control of the ball');
        end
    case 'DRIBBLE'
        s.held = s.held + P.dt;
        R = W.shooter.pos + (P.robotR + P.ballR) * unit([P.goalX 0] - W.shooter.pos);  % shooter's feet
        onside   = W.shooter.pos(1) <= offsideLine(W);
        laneOpen = laneClearance(b.pos, R, W.defender.pos) > P.laneClear;
        pressure = norm(W.defender.pos - b.pos) < P.pressureDist;
        ready    = s.held >= P.kickPrep;
        if ready && onside && (laneOpen || pressure || s.held > P.maxHold)
            speed = sqrt(2 * P.friction * norm(R - b.pos));   % so the ball stops at R
            b = kick(b, R, speed, P.passNoise, P.passSpeedNoise);
            s.state = 'DONE';
            W.passes = W.passes + 1;  W.lastKick = W.t;  W.lastTouch = 'PASSER';
            W = logEvent(W, 'PASSER passes to the shooter (%.2f m/s)', norm(b.vel));
        else
            if ready && ~s.logged, W = logEvent(W, 'PASSER dribbles: no pass on yet'); s.logged = true; end
            target = [min(b.pos(1) + 0.4, P.shooterMaxX), clamp(b.pos(2) + 0.5 * s.side, 2.3)];
            [s, b] = dribble(s, b, target, P);
            W.dribbleTime = W.dribbleTime + P.dt;
        end
end
W.passer = s;  W.ball = b;
end


%% ------------------------------------------------------------------
function W = shooterStep(W, P)
s = W.shooter;  b = W.ball;
switch s.state
    case 'RUN'
        if W.passes > 0
            s.state = 'RECEIVE';
        else
            s.pos = walkTowards(s.pos, findSpace(W, P), P.walkV, P.dt);
        end
    case 'RECEIVE'
        s.pos = walkTowards(s.pos, b.pos, P.walkV, P.dt);
        if canControl(s, b, P)
            [s, b] = takeControl(s, b, 'shooter', W.defender);
            W = logEvent(W, 'SHOOTER takes control of the ball');
        end
    case 'DRIBBLE'
        s.held = s.held + P.dt;
        [aim, clearance] = bestAim(W, P);
        pressure = norm(W.defender.pos - b.pos) < P.pressureDist;
        ready    = s.held >= P.kickPrep;
        if ready && (clearance > P.shotClear || pressure || s.held > P.maxHold)
            b = kick(b, aim, P.shotSpeed, P.shotNoise, 0);
            s.state = 'DONE';
            W.shots = W.shots + 1;  W.lastKick = W.t;  W.lastTouch = 'SHOOTER';
            W = logEvent(W, 'SHOOTER shoots at y = %.2f m', aim(2));
        else
            if ready && ~s.logged, W = logEvent(W, 'SHOOTER dribbles: no clear shot yet'); s.logged = true; end
            target = [min(b.pos(1) + 0.3, P.dribbleMaxX), clamp(b.pos(2) + 0.5 * s.side, 1.8)];
            [s, b] = dribble(s, b, target, P);
            W.dribbleTime = W.dribbleTime + P.dt;
        end
end
W.shooter = s;  W.ball = b;
end


%% ------------------------------------------------------------------
function target = findSpace(W, P)
% Onside, not too close to goal, and where the pass line is furthest from
% the defender (with a small preference for central spots)
x  = min(offsideLine(W) - P.onsideMargin, P.shooterMaxX);
ys = -1.5:0.5:1.5;
score = arrayfun(@(y) laneClearance(W.ball.pos, [x y], W.defender.pos) - 0.2 * abs(y), ys);
[~, best] = max(score);
target = [x ys(best)];
end


function [aim, clearance] = bestAim(W, P)
% Try spots across the goal and pick the one whose shot line stays furthest
% from both the defender and the keeper
best = -inf;
for y = linspace(-1, 1, 9) * (P.goalHalfW - P.aimInside)
    target = [P.goalX y];
    score = min(laneClearance(W.ball.pos, target, W.defender.pos), ...
                laneClearance(W.ball.pos, target, W.keeper));
    if score > best, best = score; aim = target; end
end
clearance = best;
end


%% ------------------------------------------------------------------
function W = defenderStep(W, P)
d = W.defender;  b = W.ball.pos;
dist = norm(b - d.pos);
if strcmp(d.state, 'GUARD') && dist < P.attackDist
    d.state = 'ATTACK';  W = logEvent(W, 'DEFENDER attacks the ball');
elseif strcmp(d.state, 'ATTACK') && dist > P.attackDist + 0.5
    d.state = 'GUARD';   W = logEvent(W, 'DEFENDER drops back to guard');
end
if strcmp(d.state, 'GUARD')
    goal   = [P.goalX 0];
    target = goal + P.guardDist * unit(b - goal);   % between the ball and the goal
else
    target = b;
end
d.pos = walkTowards(d.pos, target, P.defenderV, P.dt);
W.defender = d;
end


function W = keeperStep(W, P)
b = W.ball;  y = 0;                          % no shot: wait in the middle
if b.vel(1) > 0.1 && W.t >= W.lastKick + P.keeperDelay
    y = b.pos(2) + b.vel(2) * (P.keeperX - b.pos(1)) / b.vel(1);  % where it crosses our line
end
y = clamp(y, P.goalHalfW);
W.keeper = walkTowards(W.keeper, [P.keeperX y], P.keeperV, P.dt);
end


function W = rollBall(W, P)
if ~isempty(W.ball.owner), return; end       % a dribbled ball moves with its striker
speed = norm(W.ball.vel);
if speed > 0, W.ball.vel = W.ball.vel * max(speed - P.friction * P.dt, 0) / speed; end
W.ball.pos = W.ball.pos + W.ball.vel * P.dt;
end


%% ------------------------------------------------------------------
function [W, outcome] = resolve(W, old, P)
% Work out what the ball touched first during this step, then the outcome
outcome = '';
b0 = old.ball.pos;  b1 = W.ball.pos;
justCleared = strcmp(W.lastTouch, 'DEFENDER') && W.t - W.lastKick < 0.5;
hitD = inf;  hitK = inf;  hitG = inf;        % fraction of the step (0 to 1), inf = no touch
if ~justCleared
    hitD = contactTime(b0 - old.defender.pos, b1 - W.defender.pos, P.robotR + P.ballR);
end
if isempty(W.ball.owner)
    hitK = contactTime(b0 - old.keeper, b1 - W.keeper, P.keeperR + P.ballR);
end
lineX = P.goalX + P.ballR;                   % ball centre here = whole ball over the line
if b0(1) < lineX && b1(1) >= lineX
    hitG = (lineX - b0(1)) / (b1(1) - b0(1));
end
first = min([hitD hitK hitG]);
if isfinite(first), W.ball.pos = b0 + first * (b1 - b0); end   % back to where it happened

if isfinite(first) && hitK == first
    W.ball.vel = [0 0];  outcome = 'SAVE';
    W = logEvent(W, 'KEEPER saves');
elseif isfinite(first) && hitD == first
    what = 'blocks the shot';
    if strcmp(W.ball.owner, 'passer'),  what = 'tackles the passer';  W.passer.state = 'CHASE';  end
    if strcmp(W.ball.owner, 'shooter'), what = 'tackles the shooter'; W.shooter.state = 'RECEIVE'; end
    if isempty(W.ball.owner) && W.shots == 0, what = 'intercepts the pass'; end
    W.ball = kick(W.ball, W.ball.pos - [1 0], P.clearSpeed, 0.3, 0);   % back up the pitch
    W.touches = W.touches + 1;  W.lastKick = W.t;  W.lastTouch = 'DEFENDER';
    W = logEvent(W, 'DEFENDER %s and clears', what);
elseif isfinite(first)
    if abs(W.ball.pos(2)) < P.goalHalfW, outcome = 'GOAL'; else, outcome = 'MISS'; end
    W = logEvent(W, '%s: ball crosses the goal line at y = %.2f m', outcome, W.ball.pos(2));
else
    pos = W.ball.pos;
    stopped  = isempty(W.ball.owner) && all(W.ball.vel == 0);
    byDefence = strcmp(W.lastTouch, 'DEFENDER');
    if pos(1) < 0 || abs(pos(2)) > 3
        if byDefence, outcome = 'CLEARED'; else, outcome = 'MISS'; end
        W = logEvent(W, '%s: ball leaves the pitch', outcome);
    elseif byDefence && (pos(1) < P.clearSafeX || stopped)
        outcome = 'CLEARED';
        W = logEvent(W, 'CLEARED: the ball is safe');
    elseif stopped && W.shots > 0
        outcome = 'MISS';
        W = logEvent(W, 'MISS: the shot stops short');
    end
end
end


%% Small helpers
function ok = canControl(s, b, P)
ok = isempty(b.owner) && norm(s.pos - b.pos) <= P.robotR + P.ballR + 0.02 ...
     && norm(b.vel) <= P.controlSpeed;
end

function [s, b] = takeControl(s, b, who, defender)
b.owner = who;  b.vel = [0 0];
s.state = 'DRIBBLE';  s.held = 0;  s.logged = false;
s.side = -sign(defender.pos(2) - b.pos(2));  % dribble away from the defender
if s.side == 0, s.side = 1; end
end

function [s, b] = dribble(s, b, target, P)
s.pos = walkTowards(s.pos, target, P.dribbleV, P.dt);
b.pos = s.pos + P.carryGap * unit(target - s.pos);
b.vel = [0 0];
end

function b = kick(b, target, speed, angleNoise, speedNoise)
d = target - b.pos;
a = atan2(d(2), d(1)) + angleNoise * randn;
b.vel = speed * (1 + speedNoise * randn) * [cos(a) sin(a)];
b.owner = '';
end

function x = offsideLine(W)
% Offside = nearer the goal line than both the ball and the second-last opponent
x = max([min(W.keeper(1), W.defender.pos(1)), W.ball.pos(1), 0]);
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
W.events{end + 1} = sprintf(['%5.2fs  ' fmt], W.t, varargin{:});
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


%% ------------------------------------------------------------------
function folder = saveResults(results, P)
folder = fullfile(fileparts(mfilename('fullpath')), 'results');
if ~exist(folder, 'dir'), mkdir(folder); end
fid = fopen(fullfile(folder, 'summary.csv'), 'w');
fprintf(fid, 'Attack,Outcome,Seconds,Passes,Shots,DefenderTouches,DribbleSeconds\n');
for r = results'
    fprintf(fid, '%d,%s,%.2f,%d,%d,%d,%.2f\n', r.Attack, r.Outcome, r.Seconds, ...
        r.Passes, r.Shots, r.DefenderTouches, r.DribbleSeconds);
end
fclose(fid);
fid = fopen(fullfile(folder, 'events.txt'), 'w');
for r = results'
    fprintf(fid, 'Attack %d: %s\n', r.Attack, r.Outcome);
    fprintf(fid, '  %s\n', r.Events{:});
    fprintf(fid, '\n');
end
fclose(fid);
save(fullfile(folder, 'results.mat'), 'results', 'P', '-v7');
end


function showOverview(results, P, folder)
% One small pitch per attack, for up to 10 attacks with different outcomes
pick = [];  pools = {};
for name = unique({results.Outcome}, 'stable')
    pools{end + 1} = find(strcmp({results.Outcome}, name{1})); %#ok<AGROW>
end
while numel(pick) < min(10, numel(results))      % take turns between outcomes
    for j = 1:numel(pools)
        if ~isempty(pools{j}) && numel(pick) < 10
            pick(end + 1) = pools{j}(1);  pools{j}(1) = []; %#ok<AGROW>
        end
    end
end
pick = sort(pick);

fig = figure(2); clf; set(fig, 'Color', 'w', 'Position', [60 60 1400 640]);
rows = ceil(numel(pick) / 5);
for j = 1:numel(pick)
    r = results(pick(j));
    subplot(rows, 5, j);  drawPitch(P);
    plot(r.ball(:, 1), r.ball(:, 2), '-', 'Color', [1 0.8 0.2], 'LineWidth', 1.3);
    plot(r.passer(:, 1),   r.passer(:, 2),   ':', 'Color', [0.3 0.6 1]);
    plot(r.shooter(:, 1),  r.shooter(:, 2),  ':', 'Color', [0.2 0.95 1]);
    plot(r.defender(:, 1), r.defender(:, 2), ':', 'Color', [0.95 0.45 1]);
    plot(r.keeper(:, 1),   r.keeper(:, 2),   ':', 'Color', [1 0.45 0.45]);
    plot(r.ball(end, 1), r.ball(end, 2), 'o', 'MarkerFaceColor', [1 0.65 0], 'MarkerEdgeColor', 'k');
    title(sprintf('Attack %d: %s (%.1f s)', r.Attack, r.Outcome, r.Seconds), 'FontSize', 9);
end
o = {results.Outcome};
annotation(fig, 'textbox', [0 0.94 1 0.06], 'EdgeColor', 'none', 'HorizontalAlignment', 'center', ...
    'FontSize', 13, 'FontWeight', 'bold', 'String', sprintf( ...
    '%d attacks: %d goals | %d saves | %d cleared | %d misses | %d timeouts      (ball solid; passer, shooter, defender, keeper dotted)', ...
    numel(o), sum(strcmp(o, 'GOAL')), sum(strcmp(o, 'SAVE')), sum(strcmp(o, 'CLEARED')), ...
    sum(strcmp(o, 'MISS')), sum(strcmp(o, 'TIMEOUT'))));
print(fig, fullfile(folder, 'overview.png'), '-dpng', '-r150');
end


%% ------------------------------------------------------------------
function drawPitch(P)
cla; hold on; axis equal; axis([-0.15 5.2 -3.15 3.15]);
set(gca, 'XTick', [], 'YTick', []);
fill([-0.15 5.2 5.2 -0.15], [-3.15 -3.15 3.15 3.15], [0.10 0.34 0.24], 'EdgeColor', 'none');  % grass
plot([0 P.goalX P.goalX 0 0], [-3 -3 3 3 -3], 'w', 'LineWidth', 1.2);              % half pitch
plot(P.goalX + [0 0.5 0.5 0], P.goalHalfW * [-1 -1 1 1], 'w', 'LineWidth', 2);    % goal
plot(3, 0, 'w+');                                                                 % penalty mark
end


function drawScene(W, track, step, seed, outcome, P)
drawPitch(P);
set(gca, 'Position', [0.04 0.08 0.58 0.84]);
x = offsideLine(W);
plot([x x], [-3 3], '--', 'Color', [0.7 0.85 0.75]);                              % offside line
plot(track.ball(1:step, 1), track.ball(1:step, 2), '-', 'Color', [1 0.8 0.2]);    % ball trail
disc(W.passer.pos,   P.robotR,  [0.15 0.45 1]);
disc(W.shooter.pos,  P.robotR,  [0 0.85 0.9]);
disc(W.defender.pos, P.robotR,  [0.75 0.2 0.85]);
disc(W.keeper,       P.keeperR, [1 0.25 0.25]);
disc(W.ball.pos,     P.ballR,   [1 0.65 0]);
if isempty(outcome), status = 'in play'; else, status = outcome; end
title(sprintf('Attack %d   t = %.1f s   %s', seed, W.t, status), 'FontSize', 13);
lines = [{['Passer (dark blue):   ' W.passer.state]; ['Shooter (light blue): ' W.shooter.state]; ...
          ['Defender (purple):    ' W.defender.state]; ''; 'EVENTS'}; W.events(max(1, end - 9):end)'];
text(1.04, 1, lines, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
     'FontName', 'FixedWidth', 'FontSize', 10, 'Interpreter', 'none');
hold off; drawnow; pause(0.02);
end

function disc(p, r, colour)
a = linspace(0, 2 * pi, 40);
fill(p(1) + r * cos(a), p(2) + r * sin(a), colour, 'EdgeColor', 'w');
end
