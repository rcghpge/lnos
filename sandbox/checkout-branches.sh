# Checkout all remote branches to local machine
# Run script to pull all remote branches for local dev

for branch in $(git branch -r | grep -vE 'HEAD|main'); do
    git branch --track "${branch#origin/}" "$branch" 2>/dev/null
done

