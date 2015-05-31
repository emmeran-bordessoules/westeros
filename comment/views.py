from django.shortcuts import render,redirect
from .forms import CommentForm
from .models import Comment
from vote.views import hasard

def add_comment(request):
	if request.method == "POST":
		form = CommentForm(request.POST)
		if form.is_valid():
			form.save()
			return redirect('comment.views.home',)
	else:
		form = CommentForm()
	cita=hasard()
	return render(request, 'comment/add_comment.html', {'form': form,'cita':cita})

def home(request):
	Comments= Comment.objects.order_by('-id')
	cita=hasard()
	return render(request,'comment/comment.html',{'comments':Comments,'cita':cita})
